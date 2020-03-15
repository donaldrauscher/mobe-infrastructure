## Testing

### Testing ingress controller

Deploy app:
```
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/aws-alb-ingress-controller/v1.1.4/docs/examples/2048/2048-namespace.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/aws-alb-ingress-controller/v1.1.4/docs/examples/2048/2048-deployment.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/aws-alb-ingress-controller/v1.1.4/docs/examples/2048/2048-service.yaml
cat <<EOF | kubectl apply -f -
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: "2048-ingress"
  namespace: "2048-game"
  annotations:
    kubernetes.io/ingress.class: nginx
  labels:
    app: 2048-ingress
spec:
  rules:
    - host: 2048.docker.mobecloud.net
      http:
        paths:
          - backend:
              serviceName: "service-2048"
              servicePort: 80
EOF
```

Verify that it works from bastion host:
```
curl -I http://2048.docker.mobecloud.net
```

In WSL, set up an SSH tunnel:
```
ssh -D 1337 -q -C -N ubuntu@$MOBE_BASTION
```

Then open up Chrome routing traffic through SSH tunnel (regular Windows command line):
```
"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe" --proxy-server="socks5://127.0.0.1:1337" --user-data-dir="%USERPROFILE%\proxy-profile" 
```

### Testing EFS PV provisioner

Deploy simple pod which writes to PV:
```
cat <<EOF | kubectl apply -f -
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: efs-test-pvc
spec:
  storageClassName: "aws-efs"
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 1Mi
---
kind: Pod
apiVersion: v1
metadata:
  name: efs-test-pod
spec:
  containers:
  - name: test-pod
    image: gcr.io/google_containers/busybox:1.24
    command:
      - "/bin/sh"
    args:
      - "-c"
      - "touch /mnt/SUCCESS && exit 0 || exit 1"
    volumeMounts:
      - name: efs-pvc
        mountPath: "/mnt"
  restartPolicy: "Never"
  volumes:
    - name: efs-pvc
      persistentVolumeClaim:
        claimName: efs-test-pvc
```

Then mount NFS volume on bastion and check that file we just made is there:
```
sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport yourEFSsystemID.efs.yourEFSregion.amazonaws.com:/ /data/efs
sudo ls /data/efs/efs-test-pvc-*
sudo umount /data/efs
```
