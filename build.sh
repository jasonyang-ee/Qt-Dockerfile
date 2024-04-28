#!/bin/bash


# Parse arguments
POSITIONAL_ARGS=()
while [[ $# -gt 0 ]]; do
	case $1 in
	-h | --help)
		HELP=true
		shift # past argument
		;;
	-v | --version)
		# Check if has argument value
		if [[ -z "$2" ]]; then
			shift # past argument
		else
			VERSION="$2"
			shift # past argument
			shift # past value
		fi
		;;
	-b | --build)
		BUILD=true
		shift # past argument
		;;
	-p | --push)
		PUSH=true
		shift # past argument
		;;
	-r | --registry)
		# Check if has argument value
		if [[ -z "$2" ]]; then
			echo "No registry specified" >&2
			exit 1
		else
			REGISTRY="$2"
			shift # past argument
			shift # past value
		fi
		;;
	-* | --*=) # unsupported argument
		echo "Unsupported argument '$1'" >&2
		echo "See '--help' for more information"
		exit 1
		;;
	esac
done

# Check for help flag
if [[ $HELP == true ]]; then
	echo "Usage: build.sh [OPTIONS]"
	echo "Options:"
	echo "  -h, --help                 Show this help message and exit"
	echo ""
	echo "  -v, --version              No version specified, list all available versions"
	echo "  -v, --version <VERSION>    Set the version of Qt to build"
	echo ""
	echo "  -b, --build                Build the Qt Builder image"
	echo ""
	echo "  -p, --push                 Push the Qt Builder image to Docker Hub"
	echo ""
	echo "  -r, --registry <REGISTRY>  Set the registry as prefix for image name"
	exit 0
fi



# Find avaliable Versions
FULL_VERSIONS=""
MAJOR_VERSIONS=$(curl -s https://download.qt.io/official_releases/qt/ | grep -oE 'href="[[:digit:]]{1,3}.[[:digit:]]{1,3}' | sed 's/href="//')

for ITEMS in $MAJOR_VERSIONS; do
	FULL_VERSIONS+=$(curl -s https://download.qt.io/official_releases/qt/${ITEMS}/ | grep -oE 'href="[[:digit:]]{1,3}.[[:digit:]]{1,3}.[[:digit:]]{1,3}' | sed 's/href="//')
	FULL_VERSIONS+=" "     # Add a seperation between major versions
done

# If no version is specified, list all available versions
if [[ -z "$VERSION" ]]; then
	echo "Avaliable Versions:"
	echo ${FULL_VERSIONS}
	exit 0
fi

# Check if VERSION is in FULL_VERSIONS
if [[ ! "${FULL_VERSIONS[@]}" =~ "${VERSION}" ]]; then
	echo "Unsupported version '$VERSION'" >&2
	echo "See '--help' for more information"
	exit 1
fi

# Check if src folder NOT contains the file with the version
if [ ! -f "src/qt-everywhere-src-${VERSION}.tar.xz" ]; then
	echo "Downloading Qt Everywhere Version $VERSION"
	MAJOR_VERSION=$(echo $VERSION | cut -d. -f1,2)
	curl -L https://download.qt.io/official_releases/qt/${MAJOR_VERSION}/${VERSION}/single/qt-everywhere-src-${VERSION}.tar.xz -o src/qt-everywhere-src-${VERSION}.tar.xz
fi



# Build Qt Builder Image
if [[ $BUILD == true ]]; then
    echo "Compiling Qt Version $VERSION"
    docker buildx build \
		--target=artifact --output type=local,dest=$(pwd)/build-${VERSION}/ \
		--platform linux/amd64,linux/arm64 \
		--build-arg VERSION=${VERSION} \
		--cache-from=type=local,src=$(pwd)/cache/ --cache-to=type=local,dest=$(pwd)/cache/,mode=max \
		-f Dockerfile.builder .
fi

# Push Qt Builder Image
if [[ $PUSH == true ]]; then
    docker buildx build --target=building --push \
	--platform linux/amd64,linux/arm64 \
	-t $REGISTRY/qt-builder:${VERSION} \
	--build-arg VERSION=${VERSION} \
	--cache-from=type=local,src=$(pwd)/cache/ --cache-to=type=local,dest=$(pwd)/cache/,mode=max \
	-f Dockerfile.builder .
fi



# Pushover Notification
if [ -x "$(command -v ntfy)" ]; then ntfy send "build qt-builder complete"; fi