#!/usr/bin/env python3
"""Small App Store Connect helper. Keys stay in their existing private location."""
import argparse,base64,json,os,subprocess,time,urllib.request,urllib.error
from pathlib import Path

def b64(data):return base64.urlsafe_b64encode(data).rstrip(b'=')
def length(data,pos):
    n=data[pos];pos+=1
    if n&0x80:
        size=n&0x7f;n=int.from_bytes(data[pos:pos+size],'big');pos+=size
    return n,pos

def jwt(config):
    header=b64(json.dumps({'alg':'ES256','kid':config['keyId'],'typ':'JWT'},separators=(',',':')).encode())
    now=int(time.time());payload=b64(json.dumps({'iss':config['issuerId'],'iat':now,'exp':now+900,'aud':'appstoreconnect-v1'},separators=(',',':')).encode())
    signing=header+b'.'+payload
    der=subprocess.run(['openssl','dgst','-sha256','-sign',str(Path(config['keyPath']).expanduser())],input=signing,capture_output=True,check=True).stdout
    if der[0]!=0x30:raise RuntimeError('Invalid ES256 signature')
    _,pos=length(der,1);values=[]
    for _ in range(2):
        if der[pos]!=2:raise RuntimeError('Invalid ES256 integer')
        n,pos=length(der,pos+1);values.append(int.from_bytes(der[pos:pos+n],'big').to_bytes(32,'big'));pos+=n
    return (signing+b'.'+b64(b''.join(values))).decode()

class ASC:
    def __init__(self,config=None):
        path=Path(config or os.environ.get('CADENCE_ASC_CONFIG',str(Path.home()/'.config/cadence/apple.json')))
        self.config=json.loads(path.read_text());self.token=jwt(self.config)
    def request(self,path,method='GET',body=None):
        # Some local IPv6 routes to Apple's API are unavailable. Curl's IPv4
        # transport avoids changing the Mac's network configuration. The bearer
        # token is supplied through stdin, never through argv or a temporary file.
        options = ['url = '+json.dumps('https://api.appstoreconnect.apple.com'+path),
                   'request = '+json.dumps(method),
                   'header = '+json.dumps('Authorization: Bearer '+self.token),
                   'header = '+json.dumps('Content-Type: application/json'),
                   'write-out = "\\n%{http_code}"']
        if body is not None: options.append('data = '+json.dumps(json.dumps(body)))
        args=['curl','--globoff','--ipv4','--silent','--show-error','--max-time','45','--config','-']
        if method=='GET':args.extend(['--retry','2','--retry-delay','1'])
        result=subprocess.run(args,input='\n'.join(options),capture_output=True,text=True)
        if result.returncode:raise RuntimeError('App Store Connect transport failed: '+result.stderr.strip())
        raw,status=result.stdout.rsplit('\n',1)
        if not 200 <= int(status) < 300:raise RuntimeError('App Store Connect '+status+': '+raw)
        return json.loads(raw) if raw.strip() else {}
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('path');p.add_argument('--method',default='GET');p.add_argument('--body-file');p.add_argument('--config');a=p.parse_args()
    body=json.loads(Path(a.body_file).read_text()) if a.body_file else None
    print(json.dumps(ASC(a.config).request(a.path,a.method,body),indent=2))
