docker login -u acejilam

cat >sync_image.sh <<\EOF
# set -x xtrace
# export PS4='[Line:${LINENO}] '
sync() {
    address=$1
    arr=(${address//\// })
    Repo=${arr[${#arr[@]}-1]}

    for line in $(gcloud container images list-tags $address | grep -v TAGS | awk '{printf("%s@%s\n", $1,$2)}'); do
        _id=$(echo $line | awk -F'@' '{print $1}')
        tag_date=$(echo $line | awk -F'@' '{print $2}')
        _date=$(echo $tag_date | awk -F'T' '{print $1}')
        _time=$(echo $tag_date | awk -F'T' '{print $2}')

        if echo $_date | grep -q '\<[0-9]\{4\}-[0-9]\{1,2\}-[0-9]\{1,2\}\>'; then
            continue
        else
            tag=$tag_date
            flag=false

            curl -o /tmp/res.txt -s https://hub.docker.com/v2/repositories/acejilam/$Repo/tags/?page_size=1000&page=1
            res=`cat /tmp/res.txt |jq -r '.results[].name'`
            array=(${res// /,})
            len=${#array[*]}
            for item in $res; do
                if [ "$item" == "$tag" ]; then
                    flag=true
                    echo -e "\033[32m存在  acejilam/$Repo:$tag\033[0m"
                    break
                fi
            done
            if [ "$tag" == "latest" ]; then
                flag=false
            fi
            echo $len ' ------->' $flag $Repo:$tag
            if $flag; then
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

EOF
chmod +x sync_image.sh
./sync_image.sh
