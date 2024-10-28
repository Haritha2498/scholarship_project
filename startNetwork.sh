#!/bin/bash

echo "------------Register the ca admin for each organization—----------------"

docker compose -f docker/docker-compose-ca.yaml up -d
sleep 3
sudo chmod -R 777 organizations/

echo "------------Register and enroll the users for each organization—-----------"

chmod +x registerEnroll.sh

./registerEnroll.sh
sleep 3

echo "—-------------Build the infrastructure—-----------------"

docker compose -f docker/docker-compose-4org.yaml up -d
sleep 3

echo "-------------Generate the genesis block—-------------------------------"

export FABRIC_CFG_PATH=${PWD}/config

export CHANNEL_NAME=mychannel

configtxgen -profile ChannelUsingRaft -outputBlock ${PWD}/channel-artifacts/${CHANNEL_NAME}.block -channelID $CHANNEL_NAME

echo "------ Create the application channel------"

export ORDERER_CA=${PWD}/organizations/ordererOrganizations/scholarship.com/orderers/orderer.scholarship.com/msp/tlscacerts/tlsca.scholarship.com-cert.pem

export ORDERER_ADMIN_TLS_SIGN_CERT=${PWD}/organizations/ordererOrganizations/scholarship.com/orderers/orderer.scholarship.com/tls/server.crt

export ORDERER_ADMIN_TLS_PRIVATE_KEY=${PWD}/organizations/ordererOrganizations/scholarship.com/orderers/orderer.scholarship.com/tls/server.key

osnadmin channel join --channelID $CHANNEL_NAME --config-block ${PWD}/channel-artifacts/$CHANNEL_NAME.block -o localhost:7053 --ca-file $ORDERER_CA --client-cert $ORDERER_ADMIN_TLS_SIGN_CERT --client-key $ORDERER_ADMIN_TLS_PRIVATE_KEY
sleep 2
osnadmin channel list -o localhost:7053 --ca-file $ORDERER_CA --client-cert $ORDERER_ADMIN_TLS_SIGN_CERT --client-key $ORDERER_ADMIN_TLS_PRIVATE_KEY
sleep 2

export FABRIC_CFG_PATH=${PWD}/peercfg

export USER_PEER_TLSROOTCERT=${PWD}/organizations/peerOrganizations/user.scholarship.com/peers/peer0.user.scholarship.com/tls/ca.crt
export UNIVERSITY_PEER_TLSROOTCERT=${PWD}/organizations/peerOrganizations/university.scholarship.com/peers/peer0.university.scholarship.com/tls/ca.crt
export GOVAGENCY_PEER_TLSROOTCERT=${PWD}/organizations/peerOrganizations/govAgency.scholarship.com/peers/peer0.govAgency.scholarship.com/tls/ca.crt
export SCHOLARSHIPPROVIDER_PEER_TLSROOTCERT=${PWD}/organizations/peerOrganizations/scholarshipProvider.scholarship.com/peers/peer0.scholarshipProvider.scholarship.com/tls/ca.crt

export CORE_PEER_TLS_ENABLED=true
export CORE_PEER_LOCALMSPID=userMSP
export CORE_PEER_TLS_ROOTCERT_FILE=${PWD}/organizations/peerOrganizations/user.scholarship.com/peers/peer0.user.scholarship.com/tls/ca.crt
export CORE_PEER_MSPCONFIGPATH=${PWD}/organizations/peerOrganizations/user.scholarship.com/users/Admin@user.scholarship.com/msp
export CORE_PEER_ADDRESS=localhost:7051
sleep 2

echo "—---------------Join user peer0 to the channel—-------------"

echo ${FABRIC_CFG_PATH}
sleep 2
peer channel join -b ${PWD}/channel-artifacts/${CHANNEL_NAME}.block
sleep 3

echo "-----channel List----"
peer channel list

echo "—-------------user anchor peer update—-----------"


peer channel fetch config ${PWD}/channel-artifacts/config_block.pb -o localhost:7050 --ordererTLSHostnameOverride orderer.scholarship.com -c $CHANNEL_NAME --tls --cafile $ORDERER_CA
sleep 1

cd channel-artifacts

configtxlator proto_decode --input config_block.pb --type common.Block --output config_block.json
jq '.data.data[0].payload.data.config' config_block.json > config.json

cp config.json config_copy.json

jq '.channel_group.groups.Application.groups.userMSP.values += {"AnchorPeers":{"mod_policy": "Admins","value":{"anchor_peers": [{"host": "peer0.user.scholarship.com","port": 7051}]},"version": "0"}}' config_copy.json > modified_config.json

configtxlator proto_encode --input config.json --type common.Config --output config.pb
configtxlator proto_encode --input modified_config.json --type common.Config --output modified_config.pb
configtxlator compute_update --channel_id ${CHANNEL_NAME} --original config.pb --updated modified_config.pb --output config_update.pb

configtxlator proto_decode --input config_update.pb --type common.ConfigUpdate --output config_update.json
echo '{"payload":{"header":{"channel_header":{"channel_id":"'$CHANNEL_NAME'", "type":2}},"data":{"config_update":'$(cat config_update.json)'}}}' | jq . > config_update_in_envelope.json
configtxlator proto_encode --input config_update_in_envelope.json --type common.Envelope --output config_update_in_envelope.pb

cd ..

peer channel update -f ${PWD}/channel-artifacts/config_update_in_envelope.pb -c $CHANNEL_NAME -o localhost:7050  --ordererTLSHostnameOverride orderer.scholarship.com --tls --cafile $ORDERER_CA
peer channel getinfo -c $CHANNEL_NAME
sleep 1

echo "—---------------package chaincode—-------------"

peer lifecycle chaincode package scholarship.tar.gz --path ${PWD}/../Chaincode/scholarship --lang node --label scholarship_1.0
sleep 1

echo "—---------------install chaincode in user peer—-------------"

peer lifecycle chaincode install scholarship.tar.gz
sleep 3

peer lifecycle chaincode queryinstalled
sleep 1

export CC_PACKAGE_ID=$(peer lifecycle chaincode calculatepackageid scholarship.tar.gz)

echo "—---------------Approve chaincode in user peer—-------------"

# peer lifecycle chaincode approveformyorg -o localhost:7050 --ordererTLSHostnameOverride orderer.scholarship.com --channelID $CHANNEL_NAME --name scholarship --version 1.0 --package-id $CC_PACKAGE_ID --sequence 1 --tls --cafile $ORDERER_CA --waitForEvent
peer lifecycle chaincode approveformyorg -o localhost:7050 --ordererTLSHostnameOverride orderer.scholarship.com --channelID $CHANNEL_NAME --name scholarship --version 1.0 --collections-config ../Chaincode/scholarship/collection-scholarship.json --package-id $CC_PACKAGE_ID --sequence 1 --tls --cafile $ORDERER_CA --waitForEvent
sleep 2


export CORE_PEER_LOCALMSPID=userMSP
export CORE_PEER_TLS_ENABLED=true
export CORE_PEER_TLS_ROOTCERT_FILE=${PWD}/organizations/peerOrganizations/user.scholarship.com/peers/peer1.user.scholarship.com/tls/ca.crt
export CORE_PEER_MSPCONFIGPATH=${PWD}/organizations/peerOrganizations/user.scholarship.com/users/Admin@user.scholarship.com/msp
export CORE_PEER_ADDRESS=localhost:7061


sleep 2

echo "—---------------Join user peer1 to the channel—-------------"

echo ${FABRIC_CFG_PATH}
sleep 2
peer channel join -b ${PWD}/channel-artifacts/${CHANNEL_NAME}.block
sleep 3

echo "-----channel List----"
peer channel list




sleep 1
export CORE_PEER_LOCALMSPID=universityMSP
export CORE_PEER_TLS_ENABLED=true
export CORE_PEER_TLS_ROOTCERT_FILE=${PWD}/organizations/peerOrganizations/university.scholarship.com/peers/peer0.university.scholarship.com/tls/ca.crt
export CORE_PEER_MSPCONFIGPATH=${PWD}/organizations/peerOrganizations/university.scholarship.com/users/Admin@university.scholarship.com/msp
export CORE_PEER_ADDRESS=localhost:9051

echo "—---------------Join university peer0 to the channel—-------------"

peer channel join -b ${PWD}/channel-artifacts/$CHANNEL_NAME.block
sleep 1
peer channel list

echo "—-------------university anchor peer update—-----------"


peer channel fetch config ${PWD}/channel-artifacts/config_block.pb -o localhost:7050 --ordererTLSHostnameOverride orderer.scholarship.com -c $CHANNEL_NAME --tls --cafile $ORDERER_CA
sleep 1

cd channel-artifacts

configtxlator proto_decode --input config_block.pb --type common.Block --output config_block.json
jq '.data.data[0].payload.data.config' config_block.json > config.json

cp config.json config_copy.json

jq '.channel_group.groups.Application.groups.universityMSP.values += {"AnchorPeers":{"mod_policy": "Admins","value":{"anchor_peers": [{"host": "peer0.university.scholarship.com","port": 9051}]},"version": "0"}}' config_copy.json > modified_config.json

configtxlator proto_encode --input config.json --type common.Config --output config.pb
configtxlator proto_encode --input modified_config.json --type common.Config --output modified_config.pb
configtxlator compute_update --channel_id ${CHANNEL_NAME} --original config.pb --updated modified_config.pb --output config_update.pb

configtxlator proto_decode --input config_update.pb --type common.ConfigUpdate --output config_update.json
echo '{"payload":{"header":{"channel_header":{"channel_id":"'$CHANNEL_NAME'", "type":2}},"data":{"config_update":'$(cat config_update.json)'}}}' | jq . > config_update_in_envelope.json
configtxlator proto_encode --input config_update_in_envelope.json --type common.Envelope --output config_update_in_envelope.pb

cd ..

peer channel update -f ${PWD}/channel-artifacts/config_update_in_envelope.pb -c $CHANNEL_NAME -o localhost:7050  --ordererTLSHostnameOverride orderer.scholarship.com --tls --cafile $ORDERER_CA
peer channel getinfo -c $CHANNEL_NAME
sleep 1


echo "—---------------install chaincode in university peer—-------------"

peer lifecycle chaincode install scholarship.tar.gz
sleep 3

peer lifecycle chaincode queryinstalled

echo "—---------------Approve chaincode in university peer—-------------"

# peer lifecycle chaincode approveformyorg -o localhost:7050 --ordererTLSHostnameOverride orderer.scholarship.com --channelID $CHANNEL_NAME --name scholarship --version 1.0  --package-id $CC_PACKAGE_ID --sequence 1 --tls --cafile $ORDERER_CA --waitForEvent
peer lifecycle chaincode approveformyorg -o localhost:7050 --ordererTLSHostnameOverride orderer.scholarship.com --channelID $CHANNEL_NAME --name scholarship --version 1.0 --collections-config ../Chaincode/scholarship/collection-scholarship.json --package-id $CC_PACKAGE_ID --sequence 1 --tls --cafile $ORDERER_CA --waitForEvent
sleep 1



export CORE_PEER_LOCALMSPID=govAgencyMSP
export CORE_PEER_TLS_ENABLED=true
export CORE_PEER_TLS_ROOTCERT_FILE=${PWD}/organizations/peerOrganizations/govAgency.scholarship.com/peers/peer0.govAgency.scholarship.com/tls/ca.crt
export CORE_PEER_MSPCONFIGPATH=${PWD}/organizations/peerOrganizations/govAgency.scholarship.com/users/Admin@govAgency.scholarship.com/msp
export CORE_PEER_ADDRESS=localhost:11051

echo "—---------------Join govAgency peer0 to the channel—-------------"

peer channel join -b ${PWD}/channel-artifacts/$CHANNEL_NAME.block
sleep 1
peer channel list

echo "—-------------govAgency anchor peer0 update—-----------"

peer channel fetch config ${PWD}/channel-artifacts/config_block.pb -o localhost:7050 --ordererTLSHostnameOverride orderer.scholarship.com -c $CHANNEL_NAME --tls --cafile $ORDERER_CA

sleep 1

cd channel-artifacts

configtxlator proto_decode --input config_block.pb --type common.Block --output config_block.json
jq '.data.data[0].payload.data.config' config_block.json > config.json

cp config.json config_copy.json

jq '.channel_group.groups.Application.groups.govAgencyMSP.values += {"AnchorPeers":{"mod_policy": "Admins","value":{"anchor_peers": [{"host": "peer0.govAgency.scholarship.com","port": 9051}]},"version": "0"}}' config_copy.json > modified_config.json

configtxlator proto_encode --input config.json --type common.Config --output config.pb
configtxlator proto_encode --input modified_config.json --type common.Config --output modified_config.pb
configtxlator compute_update --channel_id ${CHANNEL_NAME} --original config.pb --updated modified_config.pb --output config_update.pb

configtxlator proto_decode --input config_update.pb --type common.ConfigUpdate --output config_update.json
echo '{"payload":{"header":{"channel_header":{"channel_id":"'$CHANNEL_NAME'", "type":2}},"data":{"config_update":'$(cat config_update.json)'}}}' | jq . > config_update_in_envelope.json
configtxlator proto_encode --input config_update_in_envelope.json --type common.Envelope --output config_update_in_envelope.pb

cd ..

peer channel update -f ${PWD}/channel-artifacts/config_update_in_envelope.pb -c $CHANNEL_NAME -o localhost:7050  --ordererTLSHostnameOverride orderer.scholarship.com --tls --cafile $ORDERER_CA
peer channel getinfo -c $CHANNEL_NAME
sleep 1


echo "—---------------install chaincode in govAgency peer—-------------"

peer lifecycle chaincode install scholarship.tar.gz
sleep 3

peer lifecycle chaincode queryinstalled

echo "—---------------Approve chaincode in govAgency peer—-------------"

# peer lifecycle chaincode approveformyorg -o localhost:7050 --ordererTLSHostnameOverride orderer.scholarship.com --channelID $CHANNEL_NAME --name scholarship --version 1.0 --package-id $CC_PACKAGE_ID --sequence 1 --tls --cafile $ORDERER_CA --waitForEvent
peer lifecycle chaincode approveformyorg -o localhost:7050 --ordererTLSHostnameOverride orderer.scholarship.com --channelID $CHANNEL_NAME --name scholarship --version 1.0 --collections-config ../Chaincode/scholarship/collection-scholarship.json --package-id $CC_PACKAGE_ID --sequence 1 --tls --cafile $ORDERER_CA --waitForEvent
sleep 1



export CORE_PEER_LOCALMSPID=scholarshipProviderMSP
export CORE_PEER_TLS_ENABLED=true
export CORE_PEER_TLS_ROOTCERT_FILE=${PWD}/organizations/peerOrganizations/scholarshipProvider.scholarship.com/peers/peer0.scholarshipProvider.scholarship.com/tls/ca.crt
export CORE_PEER_MSPCONFIGPATH=${PWD}/organizations/peerOrganizations/scholarshipProvider.scholarship.com/users/Admin@scholarshipProvider.scholarship.com/msp
export CORE_PEER_ADDRESS=localhost:11151


echo "—---------------Join scholarshipProvider peer0 to the channel—-------------"

peer channel join -b ${PWD}/channel-artifacts/$CHANNEL_NAME.block
sleep 1
peer channel list

echo "—-------------scholarshipProvider anchor peer0 update—-----------"

peer channel fetch config ${PWD}/channel-artifacts/config_block.pb -o localhost:7050 --ordererTLSHostnameOverride orderer.scholarship.com -c $CHANNEL_NAME --tls --cafile $ORDERER_CA

sleep 1

cd channel-artifacts

configtxlator proto_decode --input config_block.pb --type common.Block --output config_block.json
jq '.data.data[0].payload.data.config' config_block.json > config.json

cp config.json config_copy.json

jq '.channel_group.groups.Application.groups.scholarshipProviderMSP.values += {"AnchorPeers":{"mod_policy": "Admins","value":{"anchor_peers": [{"host": "peer0.scholarshipProvider.scholarship.com","port": 9051}]},"version": "0"}}' config_copy.json > modified_config.json

configtxlator proto_encode --input config.json --type common.Config --output config.pb
configtxlator proto_encode --input modified_config.json --type common.Config --output modified_config.pb
configtxlator compute_update --channel_id ${CHANNEL_NAME} --original config.pb --updated modified_config.pb --output config_update.pb

configtxlator proto_decode --input config_update.pb --type common.ConfigUpdate --output config_update.json
echo '{"payload":{"header":{"channel_header":{"channel_id":"'$CHANNEL_NAME'", "type":2}},"data":{"config_update":'$(cat config_update.json)'}}}' | jq . > config_update_in_envelope.json
configtxlator proto_encode --input config_update_in_envelope.json --type common.Envelope --output config_update_in_envelope.pb

cd ..

peer channel update -f ${PWD}/channel-artifacts/config_update_in_envelope.pb -c $CHANNEL_NAME -o localhost:7050  --ordererTLSHostnameOverride orderer.scholarship.com --tls --cafile $ORDERER_CA
peer channel getinfo -c $CHANNEL_NAME
sleep 1


echo "—---------------install chaincode in scholarshipProvider peer—-------------"

peer lifecycle chaincode install scholarship.tar.gz
sleep 3

peer lifecycle chaincode queryinstalled

echo "—---------------Approve chaincode in scholarshipProvider peer—-------------"

# peer lifecycle chaincode approveformyorg -o localhost:7050 --ordererTLSHostnameOverride orderer.scholarship.com --channelID $CHANNEL_NAME --name scholarship --version 1.0 --package-id $CC_PACKAGE_ID --sequence 1 --tls --cafile $ORDERER_CA --waitForEvent
peer lifecycle chaincode approveformyorg -o localhost:7050 --ordererTLSHostnameOverride orderer.scholarship.com --channelID $CHANNEL_NAME --name scholarship --version 1.0 --collections-config ../Chaincode/scholarship/collection-scholarship.json --package-id $CC_PACKAGE_ID --sequence 1 --tls --cafile $ORDERER_CA --waitForEvent
sleep 1




echo "—---------------Commit chaincode in Mvd peer—-------------"

peer lifecycle chaincode checkcommitreadiness --channelID $CHANNEL_NAME --name scholarship --version 1.0 --sequence 1 --collections-config ../Chaincode/scholarship/collection-scholarship.json --tls --cafile $ORDERER_CA --output json

# peer lifecycle chaincode commit -o localhost:7050 --ordererTLSHostnameOverride orderer.scholarship.com --channelID $CHANNEL_NAME --name scholarship --version 1.0 --sequence 1 --tls --cafile $ORDERER_CA --peerAddresses localhost:7051 --tlsRootCertFiles  $USER_PEER_TLSROOTCERT --peerAddresses localhost:9051 --tlsRootCertFiles $UNIVERSITY_PEER_TLSROOTCERT --peerAddresses localhost:11051 --tlsRootCertFiles $GOVAGENCY_PEER_TLSROOTCERT --peerAddresses localhost:11151 --tlsRootCertFiles $SCHOLARSHIPPROVIDER_PEER_TLSROOTCERT

peer lifecycle chaincode commit -o localhost:7050 --ordererTLSHostnameOverride orderer.scholarship.com --channelID $CHANNEL_NAME --name scholarship --version 1.0 --sequence 1 --collections-config ../Chaincode/scholarship/collection-scholarship.json --tls --cafile $ORDERER_CA --peerAddresses localhost:7051 --tlsRootCertFiles  $USER_PEER_TLSROOTCERT --peerAddresses localhost:9051 --tlsRootCertFiles $UNIVERSITY_PEER_TLSROOTCERT --peerAddresses localhost:11051 --tlsRootCertFiles $GOVAGENCY_PEER_TLSROOTCERT --peerAddresses localhost:11151 --tlsRootCertFiles $SCHOLARSHIPPROVIDER_PEER_TLSROOTCERT
sleep 1

peer lifecycle chaincode querycommitted --channelID $CHANNEL_NAME --name scholarship --cafile $ORDERER_CA