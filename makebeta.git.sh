#!/bin/bash

# assumes you have:
# - working internet connection and can contact you 'origin' repo (probably github.com)
# - the git remote called 'origin' is used
# - can be 'test run' by suppling the '-test' argument. This will create repos in '/tmp/domotest'.

TEST_REPO=0

echo $1
if [ "${1}" == "-test" ]
then
        TEST_REPO=1
fi

lowercase(){
    echo "$1" | sed "y/ABCDEFGHIJKLMNOPQRSTUVWXYZ/abcdefghijklmnopqrstuvwxyz/"
}

OS=`lowercase \`uname -s\``
#KERNEL=`uname -r`
MACH=`uname -m`

#~ DOCUMENT_ROOT="/home/linaro/dev-domoticz"
DOCUMENT_ROOT="/opt/domoticz/code"
archive_file="images/domoticz_${OS}_${MACH}.tgz"
version_file="images/version_${OS}_${MACH}.h"
history_file="images/history_${OS}_${MACH}.txt"

if [ "$TEST_REPO" -eq "1" ] && [ ! -d "/tmp/domotest/" ]
then

        # to test this script create two dummy repos
        cd /tmp
        mkdir domotest
        cd domotest
        mkdir remoterepo.git
        cd remoterepo.git
        git init --bare
        cd ..
        git clone remoterepo.git mainrepo
        cd mainrepo
        cp ${DOCUMENT_ROOT}/README.md ./
        cp ${DOCUMENT_ROOT}/INSTALL.txt ./
        cp ${DOCUMENT_ROOT}/domoticz ${DOCUMENT_ROOT}/History.txt ${DOCUMENT_ROOT}/License.txt ${DOCUMENT_ROOT}/svnversion.h ${DOCUMENT_ROOT}/domoticz.sh ${DOCUMENT_ROOT}/server_cert.pem ./
        mkdir images www scripts Config
        echo "Pre-compiled images are stored in the images branch!" > images/README.txt
        git add README.md INSTALL.txt images/README.txt
        git add domoticz History.txt License.txt svnversion.h domoticz.sh server_cert.pem
        git commit -m "first commit"
        git checkout -b develop
        git checkout -b images
        echo "Pre-compiled images are available" > images/README.txt
        git add images/README.txt
        git commit -m "initial commit images"
        tar -zcf images/test1.tar.gz README.md INSTALL.txt
        git add images/test1.tar.gz
        git commit -m "Latest Beta-release build from 'bla'; branch 'develop'"
        git push origin --all
        echo "###"
        echo "###"
        echo "###"
elif [ "$TEST_REPO" -eq "1" ]
then
        echo "cd into test repo"
        cd /tmp/domotest/mainrepo
fi

if [ "$TEST_REPO" -ne "1" ]
then
        echo "Changing directories to $DOCUMENT_ROOT..."
        cd $DOCUMENT_ROOT
fi
#### GIT
# we will need a working internet connection to make this work!
# get hash of latest commit on the REMOTE develop branch that is locally available
GIT_REMOTE_DEV_HASH_BEFORE="$(git rev-parse origin/develop)"
echo "git rem dev hash before ${GIT_REMOTE_DEV_HASH_BEFORE}"
#~ echo "${GIT_REMOTE_DEV_HASH_BEFORE}"

# make sure our repo is up-to-date with the one on origin
# for now assume the 'origin' remote is the main github repo
git fetch origin develop

# get hash of latest commit on the REMOTE develop branch that is locally available
# normal users do not use this branch but a local checked-out branch
GIT_REMOTE_DEV_HASH_AFTER="$(git rev-parse origin/develop)"
echo "git loc dev hash after ${GIT_REMOTE_DEV_HASH_AFTER}"
#~ echo "${GIT_REMOTE_DEV_HASH_AFTER}"

if [ "$GIT_REMOTE_DEV_HASH_AFTER" != "$GIT_REMOTE_DEV_HASH_AFTER" ]
then
    echo "The 'develop' branch is updated!"
    #~ exit 1
else
    echo "The 'develop' branch is up-to-date."
fi

# checkout remote development branch
git_checkout_origin_develop_command="git checkout origin/develop"
result="$(eval ${git_checkout_origin_develop_command})"

# make sure we are on the correct branch, throw error if not.
GIT_CURRENT_COMMIT="$(git rev-parse HEAD)"
if [ "${GIT_CURRENT_COMMIT}" != "${GIT_REMOTE_DEV_HASH_AFTER}" ]
then
    echo "I used '${git_checkout_origin_develop_command}' but failed to checkout the  branch!"
    echo "While there are meany reasons a checkout may fail it's probably due to uncommit changed files. Commit or stash your files and try again."
    exit 1
fi

# build Domoticz; warn user about dependent libs!
echo "Starting to build Domoticz, please keep in mind that Domoticz may depend on libs that are build independently (like libopenzwave)!"

# configure make
echo "Configuring make..."
if [ "$TEST_REPO" -ne "1" ]
then
        cmake -DCMAKE_BUILD_TYPE=Release .
        if [ $? -ne 0 ]
        then
                echo "CMake failed!";
                exit 1
        fi
        #~ #~
        # start build
        echo "Building..."
        make -j 2
        if [ $? -ne 0 ]
        then
                echo "Compilation failed!";
                exit 1
        fi

else
        echo "would have configured cmake and build the project..."
fi

echo "Success, making beta...";

#Generate the archive
echo "Generating Archive: ${archive_file}..."

###########
# go into images folder
#~ cd $DOCUMENT_ROOT/images

# checkout remote development branch
git_checkout_images_command="git checkout images"
result="$(eval ${git_checkout_images_command})"

# make sure we are on the correct branch, throw error if not.
GIT_CURRENT_COMMIT=""
GIT_CURRENT_COMMIT="$(git rev-parse HEAD)"
GIT_LOCAL_IMAGES_HASH="$(git rev-parse images)"
if [ "${GIT_CURRENT_COMMIT}" != "${GIT_LOCAL_IMAGES_HASH}" ]
then
    echo "I used '${git_checkout_images_command}' but failed to checkout the branch!"
    echo "While there are meany reasons a checkout may fail it's probably due to uncommit changed files. Commit or stash your files and try again."
    exit 1
fi
#########

cp -f svnversion.h ${version_file}
cp -f History.txt ${history_file}

if [ -f ${archive_file} ];
then
  rm ${archive_file}
fi

if [ -f ${archive_file}.sha256sum ];
then
  rm ${archive_file}.sha256sum
fi

tar -zcf ${archive_file} domoticz History.txt License.txt svnversion.h domoticz.sh server_cert.pem --exclude .svn www/ scripts/ Config/
if [ $? -ne 0 ]
then
        echo "Error creating archive!";
        exit 1
fi

echo "Creating checksum file...";
hash="$(sha256sum ${archive_file} | sed -e 's/\s.*$//') update.tgz";
echo $hash > ${archive_file}.sha256sum

if [ ! -f ${archive_file}.sha256sum ];
then
        echo "Error creating archive checksum file!";
        exit 1
fi

#######
# commit git changes
echo "Committing changes"

# stage changed files
git add ${archive_file} ${archive_file}.sha256sum ${version_file} ${history_file}

# get hash from version file
result=""
result="$(cat ${version_file})"
arr=($result)
DOMOTICZ_COMPILED_VERSION_HASH=${arr[2]}

echo "compiled version hash $DOMOTICZ_COMPILED_VERSION_HASH"

# commit
if [ "$TEST_REPO" -eq "1" ]
then
        dname=$(date +%s)
        git commit -m "Latest Beta release-build from ${DOMOTICZ_COMPILED_VERSION_HASH}-${dname}; branch 'develop'"
else
        git commit -m "Latest Beta release-build from ${DOMOTICZ_COMPILED_VERSION_HASH}; branch 'develop'"
fi

# push commit to origin
git push origin images

#cleaning up
rm -f ${version_file}
rm -f ${history_file}

echo "Done!";
exit 0;
