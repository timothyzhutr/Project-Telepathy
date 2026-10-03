"""Portable worker and explicit model setup CLI."""
import argparse,fcntl,json,os,sys,urllib.request
from pathlib import Path
from model_store import data_dir,download_models,validate_models,manifest

def main():
    parser=argparse.ArgumentParser(description='Telepathy local Kev worker')
    group=parser.add_mutually_exclusive_group()
    for option in ('serve','download-model','check-model','self-test'): group.add_argument('--'+option,action='store_true')
    parser.add_argument('--model-dir',type=Path,default=data_dir()/'models')
    parser.add_argument('--port',type=int,default=18765)
    args=parser.parse_args()
    if args.download_model:
        download_models(args.model_dir)
        try:
            url='http://127.0.0.1:'+str(args.port)
            with urllib.request.urlopen(url+'/api/health',timeout=1) as response: health=json.load(response)
            if health.get('app')=='Telepathy':
                with urllib.request.urlopen(urllib.request.Request(url+'/api/reload',data=b'{}'),timeout=1): pass
        except Exception: pass
        return
    if args.check_model:
        validate_models(args.model_dir,manifest());print('All pinned model files verified.');return
    if args.self_test:
        from kev_ranker import KevRanker
        ranker=KevRanker(args.model_dir)
        print(json.dumps(ranker.rank('作为消费者，我们有依法要求商家提供合格产品的','quanli',['权力','权利']),ensure_ascii=False));return
    from decision import DecisionService
    from server import make_server,ModelLoader
    # One worker per user, regardless of the calling app's installation location.
    lock_path=data_dir()/'.worker.lock';lock_path.parent.mkdir(parents=True,exist_ok=True)
    with lock_path.open('w') as lock:
        try: fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        except BlockingIOError: return
        service=DecisionService();loader=ModelLoader(service,args.model_dir)
        try: server=make_server(args.port,service,loader.health,loader.start)
        except OSError: raise SystemExit('Telepathy worker port is already in use.')
        loader.start();print('Telepathy worker listening on loopback.',flush=True)
        try: server.serve_forever()
        except KeyboardInterrupt: pass
        finally: server.server_close()
if __name__=='__main__': main()
