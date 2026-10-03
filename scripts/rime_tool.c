#include <rime_api.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
int main(int argc,char**argv){
  if(argc<4)return 2;
  RimeApi* api=rime_get_api();
  RIME_STRUCT(RimeTraits,traits);
  traits.shared_data_dir=realpath(argv[2],NULL);traits.user_data_dir=realpath(argv[3],NULL);chdir(traits.shared_data_dir);traits.app_name="telepathy.package";
  traits.log_dir=traits.user_data_dir;api->setup(&traits);api->initialize(&traits);
  if(!strcmp(argv[1],"deploy")){
    api->start_maintenance(True);api->join_maintenance_thread();
    int ok=api->deploy_config_file("squirrel.yaml","config_version");api->finalize();return ok?0:1;
  }
  RimeSessionId session=api->create_session();
  if(!session||!api->select_schema(session,"wanxiang")){fprintf(stderr,"Missing Wanxiang schema\n");return 1;}
  const char* samples[]={"nihao","butaixing","quanli","moxing","zhongwen"};
  for(int j=0;j<5;j++){
    api->clear_composition(session);
    for(const char*p=samples[j];*p;p++)api->process_key(session,*p,0);
    RIME_STRUCT(RimeContext,ctx);
    if(!api->get_context(session,&ctx)||ctx.menu.num_candidates<1){fprintf(stderr,"Missing candidates: %s\n",samples[j]);return 1;}
    printf("%s:",samples[j]);for(int i=0;i<ctx.menu.num_candidates;i++)printf(" %s",ctx.menu.candidates[i].text);puts("");
    if(!strcmp(samples[j],"butaixing")&&strcmp(ctx.menu.candidates[0].text,"不太行")){fprintf(stderr,"Coverage baseline changed\n");return 1;}
    api->free_context(&ctx);
  }
  api->destroy_session(session);api->finalize();return 0;
}
