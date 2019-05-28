FROM ubuntu:18.04
COPY . /perl-csv-generator
RUN apt-get update && apt-get install -y perl pdftohtml liblist-moreutils-perl libwww-perl wget