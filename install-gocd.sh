#!/bin/bash

set -e

echo "Installing jq"
brew install jq;

echo "Starting GoCD"
export GOCD_SERVER_NAME=idfc_gocd_server
export GOCD_JAVA_13_AGENT=idfc_gocd_agent_java_13
export GOCD_JAVA_15_AGENT=idfc_gocd_agent_java_15
export GOCD_NODEJS_AGENT=idfc_gocd_agent_nodejs

export GOCD_SERVER_IMAGE=gocd/gocd-server:v21.4.0
export GOCD_JAVA_13_DOCKER_IMAGE=ganeshpl/gocd-agent-alpine-3.15-java-13:v20.4.0
export GOCD_JAVA_15_DOCKER_IMAGE=ganeshpl/gocd-agent-alpine-3.15-java-15:v20.4.0
export GOCD_NODEJS_DOCKER_IMAGE=ganeshpl/gocd-agent-alpine-3.15-nodejs:v20.4.0

echo "Start pulling required docker images..."
docker image pull $GOCD_SERVER_IMAGE
docker image pull $GOCD_JAVA_13_DOCKER_IMAGE
docker image pull $GOCD_JAVA_15_DOCKER_IMAGE
docker image pull $GOCD_NODEJS_DOCKER_IMAGE
echo "Done..."

echo "Stopping existing containers..."
docker container rm -f $GOCD_SERVER_NAME
docker container rm -f $GOCD_JAVA_13_AGENT
docker container rm -f $GOCD_JAVA_15_AGENT
docker container rm -f $GOCD_NODEJS_AGENT
echo "Done..."


export GOCD_GODATA_FOLDER="/Users/$(whoami)/.gocd/godata"
rm -rf "$GOCD_GODATA_FOLDER"
mkdir -p "$GOCD_GODATA_FOLDER"
mkdir -p "$GOCD_GODATA_FOLDER/config"
mkdir -p "$GOCD_GODATA_FOLDER/plugins/external"

echo "Starting $GOCD_SERVER_NAME container..."
docker container run -v $GOCD_GODATA_FOLDER:/godata -d -p 8153:8153 -e GOCD_PLUGIN_INSTALL_docker-elastic-agents=https://github.com/gocd-contrib/docker-elastic-agents-plugin/releases/download/v3.0.0-245/docker-elastic-agents-3.0.0-245.jar --name $GOCD_SERVER_NAME gocd/gocd-server:v21.4.0
echo "Start running $GOCD_SERVER_NAME docker container..."

sleep 30

RUNNING_CONTAINERS=$(docker ps | wc -l)

if [ "$RUNNING_CONTAINERS" -eq "1" ]; then
    echo "GoCD Server Container not Running. Please Rerun the script!!"
    exit 1;
fi

until [ -f "$GOCD_GODATA_FOLDER/config/cruise-config.xml" ]
do
     sleep 5
     echo "Waiting for external plugins to be downloaded..."
done
echo "Downloaded external plugins..."

sleep 20

RUNNING_CONTAINERS=$(docker ps | wc -l)
if [ "$RUNNING_CONTAINERS" -eq "1" ]; then
    echo "GoCD Server Container not Running. Please Rerun the script!!"
    exit 1;
fi

API_RESPONSE=0
while [ $API_RESPONSE -ne 200 ]
do
  echo "Waiting for GoCD Server to Start..."
  sleep 10
  API_RESPONSE=$(curl --write-out '%{http_code}' --silent --output /dev/null 'http://localhost:8153/go/api/v1/health')
done
echo "GoCD Server Started..."


echo "Locating Agent Auto Register Key"
AGENT_AUTO_REGISTER_KEY=$(echo 'cat //cruise/server/@agentAutoRegisterKey' | xmllint --shell $GOCD_GODATA_FOLDER/config/cruise-config.xml  | grep -v ">" | cut -f 2 -d "=" | tr -d \")
echo "AGENT_AUTO_REGISTER_KEY is $AGENT_AUTO_REGISTER_KEY"


echo "Starting $GOCD_JAVA_13_AGENT container..."
docker run --name $GOCD_JAVA_13_AGENT -d -e AGENT_AUTO_REGISTER_KEY=$AGENT_AUTO_REGISTER_KEY -e AGENT_AUTO_REGISTER_RESOURCES="java,jdk13" -e AGENT_AUTO_REGISTER_HOSTNAME=$GOCD_JAVA_13_AGENT -e GO_SERVER_URL=http://$(docker inspect --format='{{(index (index .NetworkSettings.IPAddress))}}' $GOCD_SERVER_NAME):8153/go $GOCD_JAVA_13_DOCKER_IMAGE


echo "Starting $GOCD_JAVA_15_AGENT container..."
docker run --name $GOCD_JAVA_15_AGENT -d -e AGENT_AUTO_REGISTER_KEY=$AGENT_AUTO_REGISTER_KEY -e AGENT_AUTO_REGISTER_RESOURCES="java,jdk15" -e AGENT_AUTO_REGISTER_HOSTNAME=$GOCD_JAVA_15_AGENT -e GO_SERVER_URL=http://$(docker inspect --format='{{(index (index .NetworkSettings.IPAddress))}}' $GOCD_SERVER_NAME):8153/go $GOCD_JAVA_15_DOCKER_IMAGE


echo "Starting $GOCD_NODEJS_AGENT container..."
docker run --name $GOCD_NODEJS_AGENT -d -e AGENT_AUTO_REGISTER_KEY=$AGENT_AUTO_REGISTER_KEY -e AGENT_AUTO_REGISTER_RESOURCES="nodejs" -e AGENT_AUTO_REGISTER_HOSTNAME=$GOCD_NODEJS_AGENT -e GO_SERVER_URL=http://$(docker inspect --format='{{(index (index .NetworkSettings.IPAddress))}}' $GOCD_SERVER_NAME):8153/go $GOCD_NODEJS_DOCKER_IMAGE

echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo "~~~~~~~~~~~~~~~~~~~~ GoCD Setup Completed ~~~~~~~~~~~~~~~~~~~~~~~~"
echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"