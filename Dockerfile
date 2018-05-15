FROM drydock-prod.workiva.net/workiva/smithy-runner-generator:194606 as build

# Build Environment Vars
ARG BUILD_ID
ARG BUILD_NUMBER
ARG BUILD_URL
ARG GIT_COMMIT
ARG GIT_BRANCH
ARG GIT_TAG
ARG GIT_COMMIT_RANGE
ARG GIT_HEAD_URL
ARG GIT_MERGE_HEAD
ARG GIT_MERGE_BRANCH
WORKDIR /build/
ADD . /build/
ENV CODECOV_TOKEN='bQ4MgjJ0G2Y73v8JNX6L7yMK9679nbYB'
RUN echo "Starting the script sections" && \
	pub get && \
	pub publish --dry-run && \
	dartanalyzer bin && \
	dartfmt -l 80 -n --set-exit-if-changed bin && \
	tar czvf dart_build.pub.tgz LICENSE README.md pubspec.yaml bin && \
	echo "Script sections completed"
# ARG BUILD_ARTIFACTS_WEB_BUILD=/build/build.tar.gz
# ARG BUILD_ARTIFACTS_DOCUMENTATION=/build/api.tar.gz
ARG BUILD_ARTIFACTS_DART-DEPENDENCIES=/build/pubspec.lock
ARG BUILD_ARTIFACTS_PUB=/build/dart_build.pub.tgz
FROM scratch
