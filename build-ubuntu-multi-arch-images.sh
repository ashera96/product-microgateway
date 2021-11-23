#!/bin/bash
# --------------------------------------------------------------------
# Copyright (c) 2021, WSO2 Inc. (http://wso2.com) All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# -----------------------------------------------------------------------
set -e

BUILDX_VERSION=v0.7.0
BUILDX_PLATFORM=linux-amd64 # for other platforms check corresponding release: https://github.com/docker/buildx/releases/
if [[ $(uname) == 'Darwin' ]]; then
   BUILDX_PLATFORM='darwin-amd64'
fi
PLATFORMS="linux/amd64,linux/arm64"

echo "Reading product version..."
MVN_PROJECT_VERSION=$(mvn help:evaluate -Dexpression=project.version -q -DforceStdout)
echo "Product version: $MVN_PROJECT_VERSION"

ADAPTER_IMAGE="renukafernando/choreo-connect-adapter:${MVN_PROJECT_VERSION}-ubuntu"
ENFORCER_IMAGE="renukafernando/choreo-connect-enforcer:${MVN_PROJECT_VERSION}-ubuntu"
ROUTER_IMAGE="renukafernando/choreo-connect-router:${MVN_PROJECT_VERSION}-ubuntu"

GREEN='\033[0;32m' # Green colour
BOLD="\033[1m"
NC='\033[0m' # No colour

subcommand=$1

# Download the buildx plugin for docker
if [ ! -f docker-ubuntu-build/target/buildx ]; then
    echo "BuildX plugin not found"
    rm -rf docker-ubuntu-build
    mkdir -p docker-ubuntu-build/target

    echo "Downloading the buildx plugin..."
    wget https://github.com/docker/buildx/releases/download/${BUILDX_VERSION}/buildx-${BUILDX_VERSION}.${BUILDX_PLATFORM} -nv -O docker-ubuntu-build/target/buildx
fi

chmod a+x docker-ubuntu-build/target/buildx
mkdir -p ~/.docker/cli-plugins
cp docker-ubuntu-build/target/buildx ~/.docker/cli-plugins

# create build instance and use it
docker buildx create --name cc-builder --use 2> /dev/null || docker buildx use cc-builder

# build_images builds multi arch images of choreo connect components
build_images() {
  platforms=$1 # eg: linux/amd64,linux/arm64
  image_suffix=$2 # suffix such as platform
  action=$3 # --push or --load

  # replace slashes
  image_suffix=$(echo "$image_suffix" | tr "/" "-")

  ### adapter
  echo "Building Adapter image..."
  docker buildx build -t "${ADAPTER_IMAGE}${image_suffix}" --platform "$platforms" "${action}" \
    -f adapter/src/main/resources/Dockerfile.ubuntu \
    "adapter/target/docker/wso2/choreo-connect-adapter/${MVN_PROJECT_VERSION}/build/"
  ### enforcer
  echo "Building Enforcer image..."
  docker buildx build -t "${ENFORCER_IMAGE}${image_suffix}" --platform "$platforms" "${action}" \
    -f enforcer-parent/enforcer/src/main/resources/Dockerfile.ubuntu \
    "enforcer-parent/enforcer/target/docker/wso2/choreo-connect-enforcer/${MVN_PROJECT_VERSION}/build"
  ### router
  echo "Building Router image..."
  docker buildx build -t "${ROUTER_IMAGE}${image_suffix}" --platform "$platforms" "${action}" \
    -f router/src/main/resources/Dockerfile.ubuntu \
    "router/target/docker/wso2/choreo-connect-router/${MVN_PROJECT_VERSION}/build"
}

if [ "$subcommand" = "push" ]; then
  # Build and push images
  echo "Building and pushing images to registry..."
  build_images "$PLATFORMS" "" "--push"
elif [ "$subcommand" = "all" ]; then
  # Build images for all platforms
  echo "Building images for all platforms..."
  for platform in $(echo $PLATFORMS | tr "," " "); do
    echo "Build all component images for platform: $platform"
      build_images "$platform" "-${platform}" "--load"
  done
else
  # Build images for the platform of host machine
  echo "Building images matched for the platform of the host machine..."
  platform="linux/amd64"
  if [[ $(uname -m) == *"arm"* ]]; then
    echo "Building images for platform: ARM"
    platform="linux/arm64"
  else
    echo "Building images for platform: AMD"
  fi
  build_images "$platform" "-${platform}" "--load"
fi

printf "${GREEN}${BOLD}Build success${NC}\n"
