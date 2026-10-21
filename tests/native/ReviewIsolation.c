#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <unistd.h>
#include <servers/bootstrap.h>
#include <mach/mach.h>
static int read_ok(const char *path){int fd=open(path,O_RDONLY);char c=0;int n=fd<0?-1:(int)read(fd,&c,1);if(fd>=0)close(fd);return n==1&&c=='P';}
int main(int argc,char**argv){
 if(argc!=5)return 2;
 int inside=read_ok(argv[1]),outside=read_ok(argv[2]);errno=0;int fd=open(argv[3],O_CREAT|O_EXCL|O_WRONLY,0600),write_denied=fd<0&&(errno==EPERM||errno==EACCES);if(fd>=0)close(fd);
 int s=socket(AF_INET,SOCK_STREAM,0);struct sockaddr_in tcp={0};tcp.sin_family=AF_INET;tcp.sin_addr.s_addr=htonl(INADDR_LOOPBACK);errno=0;int bound=s<0?-1:bind(s,(struct sockaddr*)&tcp,sizeof(tcp)),tcp_denied=bound<0&&(errno==EPERM||errno==EACCES);if(s>=0)close(s);
 s=socket(AF_UNIX,SOCK_STREAM,0);struct sockaddr_un unix_addr={0};unix_addr.sun_family=AF_UNIX;strlcpy(unix_addr.sun_path,argv[4],sizeof(unix_addr.sun_path));errno=0;int connected=s<0?-1:connect(s,(struct sockaddr*)&unix_addr,sizeof(unix_addr)),unix_denied=connected<0&&(errno==EPERM||errno==EACCES);if(s>=0)close(s);
 errno=0;int child=fork(),fork_denied=child<0&&(errno==EPERM||errno==EACCES);if(child==0)_exit(0);if(child>0)waitpid(child,NULL,0);
 mach_port_t port=MACH_PORT_NULL;int mach=bootstrap_look_up(bootstrap_port,"com.apple.cfprefsd.daemon",&port);if(mach==KERN_SUCCESS)mach_port_deallocate(mach_task_self(),port);
 errno=0;int signalled=kill(getppid(),0),signal_denied=signalled<0&&errno==EPERM;
 printf("{\"inside_read\":%s,\"outside_read_denied\":%s,\"outside_write_denied\":%s,\"tcp_denied\":%s,\"unix_denied\":%s,\"fork_denied\":%s,\"preferences_broker_denied\":%s,\"signal_denied\":%s,\"env_absent\":%s}\n",inside?"true":"false",outside?"false":"true",write_denied?"true":"false",tcp_denied?"true":"false",unix_denied?"true":"false",fork_denied?"true":"false",mach!=KERN_SUCCESS?"true":"false",signal_denied?"true":"false",getenv("DOCVER_PARENT_SENTINEL")==NULL?"true":"false");return 0;
}
