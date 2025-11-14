export LOCAL_REPO_PATH=/temp/offline-repo

mkdir -p $LOCAL_REPO_PATH && cd $LOCAL_REPO_PATH

sudo apt-rdepends  libpmix-dev libpmix2 | grep -v "^ " | xargs -n1 apt-get download
sudo apt-rdepends  munge libmunge2   | grep -v "^ " | xargs -n1 apt-get download
sudo apt-rdepends mariadb-server mariadb-client python3-pymysql| grep -v "^ " | xargs -n1 apt-get download
sudo apt-rdepends sshpass | grep -v "^ " | xargs -n1 apt-get download
sudo apt-rdepends chrony| grep -v "^ " | xargs -n1 apt-get download
sudo apt-rdepends vim | grep -v "^ " | xargs -n1 apt-get download
sudo apt-rdepends python3 | grep -v "^ " | xargs -n1 apt-get download
sudo apt-rdepends python3-apt | grep -v "^ " | xargs -n1 apt-get download
sudo apt-rdepends build-essential | grep -v "^ " | xargs -n1 apt-get download
sudo apt-rdepends apt-transport-https | grep -v "^ " | xargs -n1 apt-get download
sudo apt-rdepends ca-certificates | grep -v "^ " | xargs -n1 apt-get download

# 修改文件名称的URL编码
for f in *%3a*; do mv "$f" "$(echo $f | sed 's/%3a/:/g')"; done

sudo dpkg-scanpackages . /dev/null | gzip -9c > Packages.gz

cd ..
tar czvf offline-repo.tar.gz ${LOCAL_REPO_PATH}

## Install All of packages
sudo dpkg -i *.deb
sudo apt-get -f install