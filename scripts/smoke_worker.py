"""Exercise the packaged executable from a relocated directory, with no Python PATH."""
import argparse,json,os,subprocess,tempfile,time,urllib.request,urllib.error
from pathlib import Path

def main():
    parser=argparse.ArgumentParser();parser.add_argument('app',type=Path);parser.add_argument('--model-dir',type=Path,required=True);args=parser.parse_args()
    app=args.app.resolve();models=args.model_dir.resolve()
    env=dict(os.environ,PYTHONPATH='',PATH='/usr/bin:/bin')
    result=subprocess.run([str(app/'Contents/MacOS/Telepathy'),'--self-test','--model-dir',str(models)],env=env,capture_output=True,text=True,check=True)
    decision=json.loads(result.stdout.strip().splitlines()[-1]);assert decision['selected_index']==1,decision
    assert decision.get('ranker')=='continuation' and decision['inferred'],decision
    print('Native command reached bundled model:',decision)
    worker=app/'Contents/Helpers/TelepathyWorker.app/Contents/MacOS/TelepathyWorker'
    with tempfile.TemporaryDirectory(prefix='telepathy isolated worker ') as name:
        env['TELEPATHY_DATA_DIR']=name;port=19765;url='http://127.0.0.1:'+str(port)
        def request(path,data=None):
            with urllib.request.urlopen(urllib.request.Request(url+path,data=data),timeout=10) as response:return json.load(response)
        for root,expected in [(Path(name)/'missing-models','model_missing'),(models,'ready')]:
            process=subprocess.Popen([str(worker),'--serve','--port',str(port),'--model-dir',str(root)],env=env,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
            try:
                deadline=time.monotonic()+40
                while True:
                    assert process.poll() is None,'Worker exited early'
                    try:
                        health=request('/api/health');status=health['status']
                        if status==expected:break
                        assert status!='error','Model initialization failed'
                    except urllib.error.URLError:pass
                    assert time.monotonic()<deadline,'Worker startup timed out';time.sleep(.2)
                snapshot=dict(revision=18,prefix='作为消费者，我们有依法要求商家提供合格产品的',pinyin='quanli',candidates=['全力','权利','权力','劝离','圈里','泉里','拳理','全','权','券','圈','泉'],candidate_ends=[6]*7+[4]*5)
                ranked=request('/api/decision',json.dumps(snapshot).encode())
                assert ranked['revision']==18
                if expected=='ready':
                    assert health['quantization']=='mxfp8',health
                    assert 0<health['backbone_weight_bytes']<health['unquantized_backbone_weight_bytes']*.6,health
                    assert ranked['status']=='ok' and ranked['order'][0]==1 and ranked['order'][7:]==list(range(7,12)),ranked
                    assert ranked['strategy']=='continuation' and ranked.get('ranker')=='continuation',ranked
                    assert ranked['inferred'] and ranked['inferred_indices']==list(range(7)),ranked
                    repeated=request('/api/decision',json.dumps(dict(snapshot,revision=20)).encode())
                    assert repeated['status']=='ok' and repeated['cache_hit'] and repeated['order'][0]==1,repeated
                    print('Repeated ranking uses copied context:',repeated)
                    for revision in (21,22):
                        continued=request('/api/decision',json.dumps(dict(snapshot,revision=revision,strategy='kev')).encode())
                        assert continued['status']=='ok' and continued['strategy']=='kev' and continued.get('ranker')!='continuation' and continued['order'][0]==1,continued
                        assert continued['order'][7:]==list(range(7,12)),continued
                        assert continued['inferred'] and continued['inferred_indices']==list(range(7)),continued
                        if revision==22:assert continued['cache_hit'],continued
                    empty=request('/api/decision',json.dumps(dict(snapshot,revision=23,prefix='',strategy='continuation')).encode())
                    assert empty['keep'] and empty['order']==list(range(12)),empty
                    assert not empty['inferred'] and empty['inferred_indices']==[],empty
                    single=request('/api/decision',json.dumps(dict(snapshot,revision=24,candidates=['权利','全'],candidate_ends=[6,4])).encode())
                    assert not single['inferred'] and single['inferred_indices']==[],single
                    print('Alternative Kev decision ranking and empty-context fallback:',continued,empty)
                else:assert ranked['status']=='unavailable' and ranked['order']==list(range(12)),ranked
                print('Worker '+expected+':',ranked)
                for prefix,language in [('I think ','english'),('天气很热，我们买点水来','chinese')]:
                    snapshot=dict(revision=19,prefix=prefix,pinyin='he',pending='he',candidates=['和','喝','何'],candidate_ends=[2,2,2])
                    routed=request('/api/language',json.dumps(snapshot).encode())
                    assert routed['status']=='ok' and routed['revision']==19,routed
                    assert routed['language']==(language if expected=='ready' else 'uncertain'),routed
                    print('Language '+expected+':',routed)
                try:
                    urllib.request.urlopen(urllib.request.Request(url+'/api/health',headers={'Origin':'https://example.com'}),timeout=5)
                    raise AssertionError('Foreign origin accepted')
                except urllib.error.HTTPError as error:assert error.code==403
                stopped=request('/api/shutdown',b'{}');assert stopped['status']=='stopping',stopped
                assert process.wait(timeout=15)==0,'Helper did not exit cleanly'
                print('Helper process exited; model and runtime memory released.')
            finally:
                if process.poll() is None:process.terminate()
                try:process.wait(timeout=10)
                except subprocess.TimeoutExpired:process.kill();process.wait()
    print('Relocated packaged-worker smoke checks passed.')
if __name__=='__main__':main()
