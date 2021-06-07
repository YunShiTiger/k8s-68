FROM centos:7
LABEL maintainer www.chenleilei.net
RUN useradd  www -u 1200 -M -s /sbin/nologin
RUN mkdir -p /var/log/nginx
RUN yum install bind-utils -y
RUN yum install -y cmake pcre pcre-devel openssl openssl-devel gd-devel \
    zlib-devel gcc gcc-c++ net-tools iproute telnet wget curl &&\
    yum clean all && \
    rm -rf /var/cache/yum/*
RUN wget https://www.chenleilei.net/soft/nginx-1.16.1.tar.gz
RUN tar xf nginx-1.16.1.tar.gz
WORKDIR nginx-1.16.1
RUN ./configure --prefix=/usr/local/nginx --with-http_image_filter_module --user=www --group=www \
    --with-http_ssl_module --with-http_v2_module --with-http_stub_status_module \
    --error-log-path=/var/log/nginx/error.log --http-log-path=/var/log/nginx/access.log \
    --pid-path=/var/run/nginx/nginx.pid
RUN make -j 4 && make install && \
    rm -rf /usr/local/nginx/html/*  && \
    echo "leilei hello" >/usr/local/nginx/html/index.html  && \
    rm -rf nginx* && \
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime &&\
    ln -sf /dev/stdout /var/log/nginx/access.log && \
    ln -sf /dev/stderr /var/log/nginx/error.log
RUN chown -R www.www /var/log/nginx
ENV LOG_DIR /var/log/nginx
ENV PATH $PATH:/usr/local/nginx/sbin
#COPY nginx.conf /usr/local/nginx/conf/nginx.conf
EXPOSE 80
WORKDIR /usr/local/nginx
CMD ["nginx","-g","daemon off;"]
