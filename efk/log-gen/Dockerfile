FROM python:3.9.6-slim as base
RUN sed -i 's#http://deb.debian.org#https://mirrors.aliyun.com#g' /etc/apt/sources.list
RUN sed -i 's#http://security.debian.org#https://mirrors.aliyun.com#g' /etc/apt/sources.list
COPY . /app
WORKDIR /app
ENV LC_ALL zh_CN.UTF-8
ENTRYPOINT ["python3"]
CMD ["app.py"]
