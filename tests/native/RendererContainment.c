#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>
#include <servers/bootstrap.h>
#include <mach/mach.h>
#include <sys/mman.h>
int main(int argc,char **argv){
 if(argc!=5)return 2;
 const char *mode=argv[1],*folder=argv[2],*outside=argv[3],*canary=argv[4];char path[4096];
 if(!strcmp(mode,"broker-baseline")){mach_port_t port=MACH_PORT_NULL;kern_return_t result=bootstrap_look_up(bootstrap_port,"com.apple.cfprefsd.daemon",&port);if(result==KERN_SUCCESS)mach_port_deallocate(mach_task_self(),port);printf("{\"mach_result\":%d}\n",result);return result==KERN_SUCCESS?0:91;}
 if(!strcmp(mode,"probe")){
  snprintf(path,sizeof(path),"%s/inside-canary",folder);int inside=open(path,O_RDONLY);char first=0;int ir=inside>=0?(int)read(inside,&first,1):-1;if(inside>=0)close(inside);
  int fd=open(canary,O_RDONLY);int re=errno;if(fd>=0)close(fd);
  int out=open(outside,O_WRONLY|O_CREAT|O_EXCL,0600);int we=errno;if(out>=0)close(out);
  int sock=socket(AF_INET,SOCK_STREAM,0);struct sockaddr_in addr;memset(&addr,0,sizeof(addr));addr.sin_family=AF_INET;addr.sin_addr.s_addr=htonl(INADDR_LOOPBACK);addr.sin_port=0;int ne=errno;int bound=sock<0?-1:bind(sock,(struct sockaddr*)&addr,sizeof(addr));if(sock>=0)ne=errno;if(sock>=0)close(sock);
  errno=0;int child=fork(),fe=errno;if(child==0)_exit(93);
  char *args[]={"/bin/echo","UNEXPECTED_EXEC",NULL};errno=0;execv(args[0],args);int ee=errno;
  mach_port_t port=MACH_PORT_NULL;kern_return_t mr=bootstrap_look_up(bootstrap_port,"com.apple.cfprefsd.daemon",&port);if(mr==KERN_SUCCESS)mach_port_deallocate(mach_task_self(),port);
  errno=0;int sr=kill(getppid(),0),se=errno;
  printf("{\"inside_read_allowed\":%s,\"mach_denied\":%s,\"mach_result\":%d,\"signal_denied\":%s,\"signal_errno\":%d,\"read_denied\":%s,\"read_errno\":%d,\"write_denied\":%s,\"write_errno\":%d,\"network_denied\":%s,\"network_errno\":%d,\"fork_denied\":%s,\"fork_errno\":%d,\"exec_denied\":%s,\"exec_errno\":%d,\"env_absent\":%s}\n",ir==1&&first=='P'?"true":"false",mr!=KERN_SUCCESS?"true":"false",mr,sr<0&&se==EPERM?"true":"false",se,fd<0&&(re==EACCES||re==EPERM)?"true":"false",re,out<0&&(we==EACCES||we==EPERM)?"true":"false",we,bound<0&&(ne==EACCES||ne==EPERM)?"true":"false",ne,child<0&&(fe==EACCES||fe==EPERM)?"true":"false",fe,ee==EACCES||ee==EPERM?"true":"false",ee,getenv("DOCVER_PARENT_SENTINEL")==NULL?"true":"false");return 0;
 }
 if(!strcmp(mode,"fsize")){signal(SIGXFSZ,SIG_IGN);snprintf(path,sizeof(path),"%s/big.bin",folder);int fd=open(path,O_WRONLY|O_CREAT|O_EXCL,0600);if(fd<0)return 4;int r=ftruncate(fd,129LL*1024*1024),e=errno;close(fd);fprintf(stderr,"ftruncate_result=%d errno=%d\n",r,e);return r<0&&e==EFBIG?42:94;}
 if(!strcmp(mode,"aggregate")){for(int i=0;i<3;i++){snprintf(path,sizeof(path),"%s/sparse-%d.bin",folder,i);int fd=open(path,O_WRONLY|O_CREAT|O_EXCL,0600);if(fd<0||ftruncate(fd,100LL*1024*1024)<0)return 5;close(fd);}return 0;}
 if(!strcmp(mode,"symlink")){snprintf(path,sizeof(path),"%s/redirect",folder);return symlink(canary,path)==0?0:6;}
 if(!strcmp(mode,"output")){for(int i=0;i<2*1024*1024;i++)putchar('A');return 0;}
 if(!strcmp(mode,"wait")||!strcmp(mode,"escape")){snprintf(path,sizeof(path),"%s/pids.json",folder);FILE *f=fopen(path,"w");if(!f)return 7;fprintf(f,"{\"converter\":%d,\"supervisor\":%d}",getpid(),getppid());fclose(f);if(!strcmp(mode,"escape")&&setpgid(0,0))return 8;for(;;)sleep(1);}
 return 3;
}
