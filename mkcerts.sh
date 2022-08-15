#!/bin/bash
 
# 如果参数不是1，给一个提示
if [ $# -ne 1 ];then
    echo "usage ./mkcert.sh level"
    exit
fi
 
#是否给private key设定密码
PRIVATE_KEY_WITH_PASSWORD="false"
PASSWORD="helloworld"
DAYS=3650
SUBJECT=""
POLICY="policy_anything"
 
 
if [ $PRIVATE_KEY_WITH_PASSWORD == "true" ];then
PASSOUT="-aes256 -passout pass:$PASSWORD"
PASSIN="-passin pass:$PASSWORD"
else
PASSOUT=""
PASSIN=""
fi
 
#keystore密码，如果不使用keytool管理秘钥，那么可以无视
PKCSPASSOUT="-passout pass:Aa123456"
TRUSTKEYSTOREPASSWORD="Aa123456"
 
#清除之前的文件
rm -rf RootCA* newCert
#创建层级的文件夹并将cnf文件进行复制
LV=0
while [ $LV -lt $1 ]
do
    mkdir RootCA$LV
    touch RootCA$LV/index.txt RootCA$LV/serial
    echo "01" > RootCA$LV/serial
    CERTIFICATE="certificate     = \$dir/RootCA$LV.pem"
    PRIVATE_KEY="private_key     = \$dir/private/RootCA$LV.key"
    cp openssl.cnf openssl.cnf.tmp
    sed -i "48 a$CERTIFICATE" openssl.cnf.tmp
    sed -i "54 a$PRIVATE_KEY" openssl.cnf.tmp
    mv openssl.cnf.tmp RootCA$LV/openssl.cnf
    ((LV=LV+1))
done

#生成证书，Root私钥->Root公钥->下级私钥->下级证书->下级证书签名
LV=0
while [ $LV -lt $1 ]
do
    echo
    echo "======= creating RootCA$LV ======="
    echo
    if [ $LV -eq 0 ];then
        cd RootCA$LV
        openssl genrsa $PASSOUT -out RootCA$LV.key 2048
        openssl req -new -x509 -days $DAYS -key RootCA$LV.key $PASSIN -out RootCA$LV.pem -subj /C=CN/ST=SC/L=CD/O=H3C/OU=Network/CN=RootCA$LV/emailAddress=RootCA$LV@eggleader.com -config openssl.cnf -sha256
    else
        cd ..; cd RootCA$LV
        openssl genrsa $PASSOUT -out RootCA$LV.key 2048
        openssl req -new -x509 -days $DAYS -key RootCA$LV.key $PASSIN -out RootCA$LV.crt -subj /C=CN/ST=SC/L=CD/O=H3C/OU=Network/CN=RootCA$LV/emailAddress=RootCA$LV@eggleader.com -config openssl.cnf
        openssl ca -ss_cert RootCA$LV.crt -cert ../RootCA$[$LV-1]/RootCA$[$LV-1].pem -keyfile ../RootCA$[$LV-1]/RootCA$[$LV-1].key $PASSIN -config openssl.cnf -policy $POLICY -out RootCA$LV.pem -outdir ./ -extensions v3_ca -batch
    fi
    ((LV=LV+1))
done

# 创建.pem文件
((LV=LV-1))
echo
echo "======= creating Server.pem ======="
echo
openssl genrsa $PASSOUT -out Server.key 2048
openssl req -new -x509 -days $DAYS -key Server.key $PASSIN -out Server.csr -subj /C=CN/ST=SC/L=CD/O=H3C/OU=Network/CN=Server/emailAddress=RootCA$LV@eggleader.com -config openssl.cnf
openssl ca -ss_cert Server.csr -cert RootCA$LV.pem -keyfile RootCA$LV.key $PASSIN -config openssl.cnf -policy $POLICY -out Server.pem -outdir ./ -batch
echo
echo "======= creating Client.pem ======="
echo
openssl genrsa $PASSOUT -out Client.key 2048
openssl req -new -x509 -days $DAYS -key Client.key $PASSIN -out Client.csr -subj /C=CN/ST=SC/L=CD/O=H3C/OU=Network/CN=Client/emailAddress=RootCA$LV@eggleader.com -config openssl.cnf
openssl ca -ss_cert Client.csr -cert RootCA$LV.pem -keyfile RootCA$LV.key $PASSIN -config openssl.cnf -policy $POLICY -out Client.pem -outdir ./  -batch
echo
echo "======= verify Server.pem Client.pem ======="
echo
cp RootCA$LV.pem RootCA$LV.pem.bak
ROOTS=0
while [ $ROOTS -lt $LV ]
do
    cat ../RootCA$ROOTS/RootCA$ROOTS.pem >> RootCA$LV.pem
    ((ROOTS+=1))
done
openssl verify -CAfile RootCA$LV.pem Server.pem Client.pem
echo
echo "======= collect cert ======="
echo
cd ..;mkdir newCert
mv RootCA$LV/Server.key RootCA$LV/Server.pem RootCA$LV/Client.key RootCA$LV/Client.pem RootCA$LV/RootCA$LV.key RootCA$LV/RootCA$LV.pem newCert
 
 
echo
echo "======= verify the cert and private key ======="
echo
cd newCert
openssl rsa -modulus -noout -in Server.key | openssl md5
openssl x509 -modulus -noout -in Server.pem | openssl md5
openssl rsa -modulus -noout -in Client.key | openssl md5
openssl x509 -modulus -noout -in Client.pem | openssl md5
 
#generate pkcs12 for java program
echo
echo "======= generate pkcs12 without chain for java program ======="
echo
openssl pkcs12 -export -in Server.pem -inkey Server.key -name Server $PKCSPASSOUT  -out Server.p12
openssl pkcs12 -export -in Client.pem -inkey Client.key -name Client $PKCSPASSOUT  -out Client.p12
keytool -import -alias Client -keystore ServerTrust.p12 -storepass $TRUSTKEYSTOREPASSWORD -noprompt -file Client.pem
keytool -import -alias Server -keystore ClientTrust.p12 -storepass $TRUSTKEYSTOREPASSWORD -noprompt -file Server.pem
 
echo
echo "======= generate pkcs12 with chain for java program ======="
echo
openssl pkcs12 -export -chain -CAfile RootCA$LV.pem -in Server.pem -inkey Server.key -name Server $PKCSPASSOUT  -out Server_wc.p12
openssl pkcs12 -export -chain -CAfile RootCA$LV.pem -in Client.pem -inkey Client.key -name Client $PKCSPASSOUT  -out Client_wc.p12