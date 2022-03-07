#!/bin/bash
cat >sync_image.sh <<\EOF
docker login -u acejilam

#set -x xtrace
#export PS4='[Line:${LINENO}] '
sync() {
  address=$1
  arr=(${address//\// })
  Repo=${arr[${#arr[@]} - 1]}
  curl -o ~/res.txt -s https://hub.docker.com/v2/repositories/acejilam/$Repo/tags/?page_size=1000
  page=1
  res=$(echo "$(cat ~/res.txt | jq -r '.results[].name')")

  OLD_IFS="$IFS"
  IFS=" "
  arr=($res)
  IFS="$OLD_IFS"
  len=0
  for s in ${arr[@]}; do
    ((len++))
  done

  a=0
  echo "gcloud container images list-tags $address"
  for tag in $(gcloud container images list-tags $address); do
    if [[ "$tag" == "TAGS:" ]] || [[ "$tag" == "DIGEST:" ]]; then
      continue
    else
      if [[ "$tag" =~ [0-9a-zA-Z]{12}$ ]]; then
        continue
      else
        if [[ "$tag" =~ .*?,.*?$ ]]; then
          continue
        else
          ((a++))
        fi
      fi
    fi
  done
  echo $address [$a] 已转存 $len $arr
  if [[ $a == $len ]]; then
    return
  fi


  for tag in $(gcloud container images list-tags $address); do
    if [[ "$tag" == "TAGS:" ]] || [[ "$tag" == "DIGEST:" ]]; then
      continue
    else
      if [[ "$tag" =~ [0-9a-zA-Z]{12}$ ]]; then
        continue
      else
        ((a++))
        if [[ "$tag" =~ .*?,.*?$ ]]; then
          continue
        fi
        # 判断镜像是否存在
        flag=false
        for item in $res; do
          if [ "$item" == "$tag" ]; then
            echo -e "\033[32m存在  acejilam/$Repo:$tag\033[0m"
            flag=true
            break
          fi
        done
        if [ "$tag" == "latest" ]; then
          flag=false
        fi

        if $flag; then
          echo $len ' ------->' 存在 $Repo:$tag
          continue
        else
          echo -e "\033[34mpulling  $address:$tag\033[0m"
          docker pull $address:$tag
          docker tag $address:$tag acejilam/$Repo:$tag
          docker push acejilam/$Repo:$tag
          echo -e "\033[32msync  acejilam/$Repo:$tag\033[0m"
          docker rmi acejilam/$Repo:$tag
          docker rmi $address:$tag
        fi
      fi
    fi
  done
}
sync 'k8s.gcr.io/kube-state-metrics/kube-state-metrics'
sync 'k8s.gcr.io/ingress-nginx/controller'
sync 'k8s.gcr.io/networking/ip-masq-agent-amd64'
sync 'k8s.gcr.io/sig-storage/csi-snapshotter'
sync 'k8s.gcr.io/sig-storage/csi-attacher'
sync 'k8s.gcr.io/sig-storage/hostpathplugin'
sync 'k8s.gcr.io/sig-storage/livenessprobe'
sync 'k8s.gcr.io/sig-storage/csi-provisioner'
sync 'k8s.gcr.io/node-problem-detector/node-problem-detector'
sync 'k8s.gcr.io/metrics-server-amd64'
sync 'k8s.gcr.io/fluentd-gcp'
sync 'k8s.gcr.io/sig-storage/csi-node-driver-registrar'
sync 'k8s.gcr.io/sig-storage/csi-resizer'
sync 'k8s.gcr.io/coredns'
sync 'gcr.io/google-samples/gb-frontend'
sync 'k8s.gcr.io/pause'
sync 'k8s.gcr.io/kube-controller-manager'
sync 'k8s.gcr.io/kube-scheduler '
sync 'k8s.gcr.io/kube-proxy'
sync 'k8s.gcr.io/kube-apiserver'
sync 'k8s.gcr.io/etcd'
sync 'k8s.gcr.io/coredns/coredns'
EOF
chmod +x sync_image.sh
bash sync_image.sh
