docker build --platform linux/amd64 -t v2rayng-builder .

docker run --rm  \
      --platform linux/amd64 \
      -v $(pwd):/project \
      -v $(pwd)/apk-output:/apk \
      v2rayng-builder \
      bash /project/build-apk.sh
