#!/bin/bash

get_all_tag() {
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

sync() {
	xxx=(${1//,/ })
	address=${xxx[0]}
	Pre=${xxx[1]}
	args=(${address//\// })
	Repo=${args[${#args[@]} - 1]}
	page=1
	all_tag=$(get_all_tag https://hub.docker.com/v2/repositories/acejilam/"$Pre$Repo"/tags/?page_size=1000)
	OLD_IFS="$IFS"
	IFS=" "
	arr=($all_tag)
	IFS="$OLD_IFS"
	len=0
	for s in ${arr[@]}; do
		if [[ "$s" != "latest" ]]; then
			((len++))
		fi
	done

	total=0
	echo "gcloud container images list-tags $address"
	for tag in $(gcloud container images list-tags $address | xargs -n 1 | grep -v -E 'DIGEST|TAGS|TIMESTAMP'); do
		if [[ "$tag" == "TAGS:" ]] || [[ "$tag" == "DIGEST:" ]] || [[ "$tag" =~ [0-9a-zA-Z]{12}$ ]] || [[ "$tag" =~ [0-9T:\-]{15}$ ]] || [[ "$tag" =~ ^sha256.* ]]; then
			continue
		else
            per_tags=(${tag//,/ })
			for per_tag in ${per_tags[@]}; do
            	if [ "$per_tag" != "latest" ]; then
                    echo "<-------: $per_tag"
                    ((total++))
				fi
            done
		fi
	done
	echo "$address [$total] 已转存 $len"
	echo $all_tag
	if [[ $total == $len ]]; then
		return
	fi

	for tag in $(gcloud container images list-tags $address | xargs -n 1 | grep -v -E 'DIGEST|TAGS|TIMESTAMP'); do
		if [[ "$tag" == "TAGS:" ]] || [[ "$tag" == "DIGEST:" ]] || [[ "$tag" =~ [0-9a-zA-Z]{12}$ ]] || [[ "$tag" =~ [0-9T:\-]{15}$ ]] || [[ "$tag" =~ ^sha256.* ]]; then
			continue
		else
			per_tags=(${tag//,/ })
			for per_tag in ${per_tags[@]}; do
				# 判断镜像是否存在
				flag=false
				for item in $all_tag; do
					if [ "$item" == "$per_tag" ]; then
						echo -e "\033[32m存在  acejilam/$Pre$Repo:$per_tag\033[0m"
						flag=true
						break
					fi
				done
				if [ "$per_tag" == "latest" ]; then
					flag=false
				fi
				if $flag; then
					continue
				else
					address=$(echo $address)
					echo -e "\033[34m pulling  $address:$per_tag\033[0m"
					docker pull $address:$per_tag
					docker tag $address:$per_tag acejilam/$Pre$Repo:$per_tag
					docker push acejilam/$Pre$Repo:$per_tag
					((len++))
					((lest = total - len))
					echo -e "\033[32m $lest sync  acejilam/$Pre$Repo:$per_tag\033[0m"
					docker rmi acejilam/$Pre$Repo:$per_tag
					docker rmi $address:$per_tag
				fi
			done

		fi

	done
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
# sync gcr.io/tekton-releases/github.com/tektoncd/dashboard/cmd/dashboard,tekton-
