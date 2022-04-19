


#!/bin/bash

#set -x xtrace
#export PS4='[Line:${LINENO}] '

get_docker_all_tag() {
  url=$1
  curl -o ~/res.txt -s $url
  tags=$(echo "$(cat ~/res.txt | jq -r '.results[].name')")
  next=$(echo "$(cat ~/res.txt | jq -r '.next')")
  while [[ $next != null ]]; do
    curl -o ~/res.txt -s $next
    tmp_tags=$(echo "$(cat ~/res.txt | jq -r '.results[].name')")
    next=$(echo "$(cat ~/res.txt | jq -r '.next')")
    tags="$tags $tmp_tags"
  done
  echo $tags
}



get_quay_all_tag() {
  address=$1
  quay_address=${address/quay.io\//}
      page=1
  len="100"
  tags=""
  while [[ $len -eq 100 ]]; do
    curl -o ~/res.txt -s "https://quay.io/api/v1/repository/$quay_address/tag/?limit=100&page=$page&onlyActiveTags=true"
    tmp_page=$(cat ~/res.txt | jq -r '.tags[].name')
    len=$(echo $tmp_page | awk -F ' ' '{print}' | wc -w)
    tags="$tmp_page $tags"
    ((page++))
  done
  echo $tags
}

gcr() {
  address=$1
  Pre=$2
  docker_all_tags=$3
  docker_exists_count=$4
  total=0
  docker_all_tags=(${docker_all_tags// / })

  echo "gcloud container images list-tags $address"
  for tag in $(gcloud container images list-tags "$address" | xargs -n 1 | grep -v -E 'DIGEST|TAGS|TIMESTAMP'); do
    if [[ "$tag" == "TAGS:" ]] || [[ "$tag" == "DIGEST:" ]] || [[ "$tag" =~ [0-9a-zA-Z]{12}$ ]] || [[ "$tag" =~ [0-9T:\-]{15}$ ]] || [[ "$tag" =~ ^sha256.* ]]; then
      continue
    else
      gcr_tags=(${tag//,/ })
      for gcr_tag in ${gcr_tags[@]}; do
        if [ "$gcr_tag" != "latest" ]; then
          echo "<-------: $gcr_tag"
          ((total++))
        fi
      done
    fi
  done
  echo "$address [$total] 已转存 $docker_exists_count"
  echo "$docker_all_tags"
  if [[ $total == $docker_exists_count ]]; then
    return
  fi

  for tag in $(gcloud container images list-tags $address | xargs -n 1 | grep -v -E 'DIGEST|TAGS|TIMESTAMP'); do
    if [[ "$tag" == "TAGS:" ]] || [[ "$tag" == "DIGEST:" ]] || [[ "$tag" =~ [0-9a-zA-Z]{12}$ ]] || [[ "$tag" =~ [0-9T:\-]{15}$ ]] || [[ "$tag" =~ ^sha256.* ]]; then
      continue
    else
      gcr_tags=(${tag//,/ })
      for gcr_tag in ${gcr_tags[@]}; do
        # 判断镜像是否存在
        flag=false
        for item in $docker_all_tags; do
          if [ "$item" == "$gcr_tag" ]; then
            echo -e "\033[32m存在  acejilam/$Pre$Repo:$gcr_tag\033[0m"
            flag=true
            break
          fi
        done
        if [ "$gcr_tag" == "latest" ]; then
          flag=false
        fi
        if $flag; then
          continue
        else
          address=$(echo $address)
          echo -e "\033[34m pulling  $address:$gcr_tag\033[0m"
          docker pull $address:$gcr_tag
          docker tag $address:$gcr_tag acejilam/$Pre$Repo:$gcr_tag
          docker push acejilam/$Pre$Repo:$gcr_tag
          ((docker_exists_count++))
          ((lest = total - docker_exists_count))
          echo -e "\033[32m $lest sync  acejilam/$Pre$Repo:$gcr_tag\033[0m"
          docker rmi acejilam/$Pre$Repo:$gcr_tag
          docker rmi $address:$gcr_tag
        fi
      done

    fi

  done
}

ghcr() {

  address=$1
  Pre=$2
  docker_all_tags=$3
  docker_exists_count=$4
  echo $address
  echo $Pre
  echo $docker_all_tags
  echo $docker_exists_count

  repo=${address#*ghcr.io/}

  curl -o 1.txt https://ghcr.io/token\?scope\="repository:$repo:pull"
  token=$(cat 1.txt |jq -r .token)

  curl -o res.txt -H "Authorization: Bearer $token" https://ghcr.io/v2/$repo/tags/list
  ghcr_all_tags=`cat res.txt|jq -r .tags[]`
  echo ghcr_all_tags
  total=0
  ghcr_all_tags=(${ghcr_all_tags// / })
  docker_all_tags=(${docker_all_tags// / })
  for quay_tag in ${ghcr_all_tags[@]}; do
    quay_tag=$(echo $quay_tag | sed 's/ //g') # 去掉空格
    if [ "$quay_tag" != "latest" ]; then
      echo "<-------: $quay_tag"
      ((total++))
    fi
  done
  echo "$address [$total] quay已转存 $docker_exists_count"
  for quay_tag in ${ghcr_all_tags[@]}; do
    quay_tag=$(echo $quay_tag | sed 's/ //g') # 去掉空格

    # 判断镜像是否存在
    flag=false
    for item in $docker_all_tags; do
      if [ "$item" == "$quay_tag" ]; then
        echo -e "\033[32m存在  acejilam/$Pre$Repo:$quay_tag\033[0m"
        flag=true
        break
      fi
    done
    if [ "$quay_tag" == "latest" ]; then
      flag=false
    fi
    if $flag; then
      continue
    else
      address=$(echo $address)
      echo -e "\033[34m pulling  $address:$quay_tag\033[0m"
      docker pull $address:$quay_tag
      docker tag $address:$quay_tag acejilam/$Pre$Repo:$quay_tag
      docker push acejilam/$Pre$Repo:$quay_tag
      ((docker_exists_count++))
      ((lest = total - docker_exists_count))
      echo -e "\033[32m $lest sync  acejilam/$Pre$Repo:$quay_tag\033[0m"
      docker rmi acejilam/$Pre$Repo:$quay_tag
      docker rmi $address:$quay_tag
    fi
  done

}

quay() {
  address=$1
  Pre=$2
  docker_all_tags=$3
  docker_exists_count=$4
  quay_all_tags=$(get_quay_all_tag "$address")
  echo quay_all_tags
  total=0
  quay_all_tags=(${quay_all_tags// / })
  docker_all_tags=(${docker_all_tags// / })
  for quay_tag in ${quay_all_tags[@]}; do
    quay_tag=$(echo $quay_tag | sed 's/ //g') # 去掉空格
    if [ "$quay_tag" != "latest" ]; then
      echo "<-------: $quay_tag"
      ((total++))
    fi
  done
  echo "$address [$total] quay已转存 $docker_exists_count"
  for quay_tag in ${quay_all_tags[@]}; do
    quay_tag=$(echo $quay_tag | sed 's/ //g') # 去掉空格

    # 判断镜像是否存在
    flag=false
    for item in $docker_all_tags; do
      if [ "$item" == "$quay_tag" ]; then
        echo -e "\033[32m存在  acejilam/$Pre$Repo:$quay_tag\033[0m"
        flag=true
        break
      fi
    done
    if [ "$quay_tag" == "latest" ]; then
      flag=false
    fi
    if $flag; then
      continue
    else
      address=$(echo $address)
      echo -e "\033[34m pulling  $address:$quay_tag\033[0m"
      docker pull $address:$quay_tag
      docker tag $address:$quay_tag acejilam/$Pre$Repo:$quay_tag
      docker push acejilam/$Pre$Repo:$quay_tag
      ((docker_exists_count++))
      ((lest = total - docker_exists_count))
      echo -e "\033[32m $lest sync  acejilam/$Pre$Repo:$quay_tag\033[0m"
      docker rmi acejilam/$Pre$Repo:$quay_tag
      docker rmi $address:$quay_tag
    fi
  done
}

sync() {
  xxx=(${1//,/ })
  address=${xxx[0]}
  Pre=${xxx[1]}
  args=(${address//\// })
  Repo=${args[${#args[@]} - 1]}
  docker_all_tags=$(get_docker_all_tag https://hub.docker.com/v2/repositories/acejilam/"$Pre$Repo"/tags/?page_size=1000)
  echo $docker_all_tags
  OLD_IFS="$IFS"
  IFS=" "
  arr=($docker_all_tags)
  IFS="$OLD_IFS"

  docker_exists_count=0
  for already_exist_tag in "${arr[@]}"; do
    if [[ "$already_exist_tag" != "latest" ]]; then
      ((docker_exists_count++))
    fi
  done

  case $address in
  *"quay.io"*)
    echo "包含quay.io"
    quay "$address" "$Pre" "$docker_all_tags" "$docker_exists_count"
    ;;
  *"ghcr.io"*)
      echo "包含ghcr.io"
      ghcr "$address" "$Pre" "$docker_all_tags" "$docker_exists_count"
      ;;
  *"gcr.io"*)
    echo "包含gcr.io"
    gcr "$address" "$Pre" "$docker_all_tags" "$docker_exists_count"
    ;;
  *) echo "不包含" ;;
  esac

}

#sync 'k8s.gcr.io/kube-state-metrics/kube-state-metrics'
#sync 'k8s.gcr.io/ingress-nginx/controller'
#sync 'k8s.gcr.io/networking/ip-masq-agent-amd64'
#sync 'k8s.gcr.io/sig-storage/csi-snapshotter'
#sync 'k8s.gcr.io/sig-storage/csi-attacher'
#sync 'k8s.gcr.io/sig-storage/hostpathplugin'
#sync 'k8s.gcr.io/sig-storage/livenessprobe'
#sync 'k8s.gcr.io/sig-storage/csi-provisioner'
#sync 'k8s.gcr.io/node-problem-detector/node-problem-detector'
#sync 'k8s.gcr.io/metrics-server-amd64'
#sync 'k8s.gcr.io/fluentd-gcp'
#sync 'k8s.gcr.io/sig-storage/csi-node-driver-registrar'
#sync 'k8s.gcr.io/sig-storage/csi-resizer'
#sync 'k8s.gcr.io/coredns'
#sync 'gcr.io/google-samples/gb-frontend'
#sync 'k8s.gcr.io/pause'
#sync 'k8s.gcr.io/kube-controller-manager'
#sync 'k8s.gcr.io/kube-scheduler '
#sync 'k8s.gcr.io/kube-proxy'
#sync 'k8s.gcr.io/kube-apiserver'
#sync 'k8s.gcr.io/etcd'
#sync 'k8s.gcr.io/coredns/coredns'
#EOF
#chmod +x sync_image.sh
#bash sync_image.sh

sync $1
#sync ghcr.io/dexidp/dex,argocd-

#sync gcr.io/tekton-releases/github.com/tektoncd/dashboard/cmd/dashboard,tekton-

#sync quay.io/jetstack/cert-manager-controller,jetstack-

