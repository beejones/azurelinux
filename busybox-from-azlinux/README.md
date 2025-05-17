# Building busybox

## build
```
sudo apt update
sudo apt install -y make gcc g++ wget curl acl zstd rpm
rm -rf build/*
cd toolkit
./pkgbld.sh -p busybox -f -nls -la out/RPMS/x86_64/
```