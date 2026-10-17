"""Сценарии CLI: повторный запуск, offline, чужие ресурсы, очистка после ошибки."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]
MOCK = r'''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
p=Path(os.environ['MOCK_STATE'])
s=json.loads(p.read_text()); a=sys.argv[1:]; s['calls'].append(a)
def done(out='', code=0):
 p.write_text(json.dumps(s)); print(out, end='\n' if out else ''); sys.exit(code)
if a[0]=='info': done('ok')
if a[:2]==['image','inspect']:
 if a[2] not in s['images']: done(code=1)
 done('[]' if '--format' in a else '{}')
if a[0]=='pull':
 s['images'].append(a[1]); done()
if a[0]=='build':
 s['images'].append(a[a.index('-t')+1]); done('CACHED')
if a[:2]==['container','inspect']:
 name=a[-1]
 if name not in s['containers']: done(code=1)
 done(s['containers'][name] if '--format' in a else '{}')
if a[0]=='rm':
 s['containers'].pop(a[-1],None); done()
if a[0]=='run':
 if '--name' in a:
  s['containers'][a[a.index('--name')+1]]='org-scripts'; done('container-id')
 if 'id' in a: done('10001')
 if 'ghcr.io/hadolint/hadolint:v2.15.1' in a:
  text=sys.stdin.read()
  if 'alpine:latest' in text: done('DL3007 DL3018 DL3019 DL3025',1)
  done()
 if 'python:3.12-slim' in a: done('50000 100000\n67108864\n64')
 if 'club-volume-demo:1.0' in a:
  if 'cat' in a: done('written by container 1')
  if 'sh' in a: done()
  done('This file came from the image.')
 done()
if a[0]=='volume':
 name=a[-1]
 if a[1]=='inspect':
  if name not in s['volumes']: done(code=1)
  done('org-scripts' if '--format' in a else '{}')
 if a[1]=='create': s['volumes'].append(name); done(name)
 if a[1]=='rm': s['volumes'].remove(name); done()
if a[0]=='save': Path(a[a.index('-o')+1]).write_bytes(b'archive for signature test'); done()
if a[0] in ('load','stop','logs','exec','ps','history'): done()
if a[0]=='compose':
 if a[1]=='version': done('v2.30.0')
 if 'exec' in a and 'GET' in a: done(str(s['visits']))
 if 'up' in a: s['visits']+=1
 done()
done('unsupported mock call: '+repr(a),1)
'''
CURL = r'''#!/usr/bin/env python3
import json,os
from pathlib import Path
p=Path(os.environ['MOCK_STATE']); s=json.loads(p.read_text())
s['calls'].append(['curl']+__import__('sys').argv[1:])
p.write_text(json.dumps(s))
if os.environ.get('MOCK_HTTP_FAIL'): raise SystemExit(1)
print('{"status":"healthy"}' if s.get('mode')=='harbor' else 'Hello from multistage! UID=10001' if s.get('mode')=='multistage' else
      '{"status":"ok","backend":"'+('redis' if s.get('mode')=='compose' else 'memory')+'"}')
'''


class ScriptTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.repo = self.root / 'repo with spaces'
        shutil.copytree(REPO, self.repo, ignore=shutil.ignore_patterns('.git', '.state', '*.pptx', '__pycache__'))
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        for name, text in [('docker', MOCK), ('curl', CURL), ('sleep', '#!/bin/sh\nexit 0\n')]:
            p = self.bin / name
            p.write_text(text)
            p.chmod(0o755)
        self.state = self.root / 'state.json'
        self.state.write_text(json.dumps({'calls': [], 'images': [], 'containers': {}, 'volumes': [], 'visits': 0}))
        self.env = dict(os.environ, PATH=str(self.bin)+os.pathsep+os.environ['PATH'], MOCK_STATE=str(self.state), TMPDIR=str(self.root))

    def tearDown(self):
        self.tmp.cleanup()

    def read(self):
        return json.loads(self.state.read_text())

    def write(self, state):
        self.state.write_text(json.dumps(state))

    def run_script(self, name, success=True, pasted=False):
        script=self.repo/'org_scripts'/name
        command=['bash','-c',script.read_text()] if pasted else ['bash',str(script)]
        result = subprocess.run(command, cwd=self.repo, env=self.env, capture_output=True, text=True)
        if success:
            self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0)
        self.assertFalse(list(self.root.glob('docker-workshop.*')))
        self.assertFalse(any(c[:2] in (['image','rm'], ['system','prune'], ['builder','prune']) or c[0]=='rmi' for c in self.read()['calls']))
        return result

    def test_nginx_twice_keeps_image_and_cleans_container(self):
        self.run_script('basic/01-nginx.sh')
        self.env['WORKSHOP_OFFLINE']='1'
        self.run_script('basic/01-nginx.sh',pasted=True)
        s=self.read()
        self.assertEqual(sum(c[0]=='pull' for c in s['calls']),1)
        self.assertIn('nginx:stable', s['images'])
        self.assertFalse(s['containers'])

    def test_offline_missing_image_never_pulls(self):
        self.env['WORKSHOP_OFFLINE']='1'
        self.run_script('basic/01-nginx.sh',success=False)
        self.assertFalse(any(c[0]=='pull' for c in self.read()['calls']))

    def test_existing_unowned_container_survives(self):
        s=self.read(); s['containers']['org-workshop-nginx']='someone-else'; self.write(s)
        self.run_script('basic/01-nginx.sh',success=False)
        self.assertEqual(self.read()['containers']['org-workshop-nginx'],'someone-else')
        self.assertFalse(any(c[0]=='rm' for c in self.read()['calls']))

    def test_nginx_http_failure_cleans_only_owned_container(self):
        self.env['MOCK_HTTP_FAIL']='1'
        self.run_script('basic/01-nginx.sh',success=False)
        self.assertFalse(self.read()['containers'])

    def test_dockerfile_twice_does_not_modify_source(self):
        source=self.repo/'app/app.py'; original=source.read_bytes()
        self.run_script('basic/02-dockerfile.sh')
        self.env['WORKSHOP_OFFLINE']='1'
        self.run_script('basic/02-dockerfile.sh',pasted=True)
        self.assertEqual(source.read_bytes(),original)
        self.assertIn('club-demo:cache-demo',self.read()['images'])

    def test_compose_twice_preserves_volume_and_verifies_counter(self):
        s=self.read(); s['mode']='compose'; self.write(s)
        self.run_script('basic/03-compose.sh')
        self.env['WORKSHOP_OFFLINE']='1'
        self.run_script('basic/03-compose.sh',pasted=True)
        calls=self.read()['calls']
        self.assertFalse(any('-v' in c for c in calls if 'down' in c))
        self.assertEqual(self.read()['visits'],4)

    def test_advanced_examples_twice(self):
        for script,mode in [('01-cgroups.sh',''),('02-multistage.sh','multistage'),
                            ('03-hadolint.sh',''),('04-openssl.sh',''),('05-volumes.sh','')]:
            with self.subTest(script=script):
                s=self.read(); s['mode']=mode; self.write(s)
                self.env['WORKSHOP_OFFLINE']='0'
                self.run_script('advanced/'+script)
                self.env['WORKSHOP_OFFLINE']='1'
                self.run_script('advanced/'+script,pasted=True)
        self.assertFalse(self.read()['volumes'])
        self.assertFalse(self.read()['containers'])

    def test_harbor_orchestration_twice_keeps_data(self):
        s=self.read(); s['mode']='harbor'; self.write(s)
        data=self.repo/'harbor/runtime/data'; data.mkdir(parents=True)
        marker=data/'keep-me'; marker.write_text('retained')
        self.run_script('basic/04-harbor.sh')
        self.env['WORKSHOP_OFFLINE']='1'
        self.run_script('basic/04-harbor.sh',pasted=True)
        self.assertEqual(marker.read_text(),'retained')
        calls=self.read()['calls']
        self.assertEqual(sum('trivy' in c and '--download-db-only' in c for c in calls),1)
        self.assertFalse(any('down' in c for c in calls))
        self.assertFalse(any(c[0] in ('build', 'login', 'tag', 'push', 'pull') and not (c[0] == 'pull' and c[1].startswith('goharbor/')) for c in calls))
        self.assertNotIn('club-demo:1.0', self.read()['images'])


    def test_harbor_never_healthy_fails_without_database_download(self):
        self.env['MOCK_HTTP_FAIL']='1'
        self.run_script('basic/04-harbor.sh',success=False)
        calls=self.read()['calls']
        self.assertFalse(any('--download-db-only' in c for c in calls))

    def test_nginx_commands_work_when_pasted_into_bash(self):
        # bash -c не задаёт $0 и BASH_SOURCE как путь к учебному скрипту.
        # Это воспроизводит вставку команд в терминал из корня репозитория.
        text=(self.repo/'org_scripts/basic/01-nginx.sh').read_text()
        result=subprocess.run(['bash','-c',text],cwd=self.repo,env=self.env,capture_output=True,text=True)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertFalse(self.read()['containers'])

    def test_all_tasks_are_self_contained(self):
        self.assertFalse((self.repo/'org_scripts/lib').exists())
        tasks=list((self.repo/'org_scripts/basic').glob('*.sh'))+list((self.repo/'org_scripts/advanced').glob('*.sh'))
        self.assertEqual(len(tasks),9)
        for script in tasks:
            text=script.read_text()
            self.assertNotIn('source ',text)
            self.assertNotIn('BASH_SOURCE',text)
            self.assertNotIn('bash "$repo_root/',text)


if __name__ == '__main__':
    unittest.main()
