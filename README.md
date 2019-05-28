## Installation

### Using docker on Windows 10.

1. Register an account on <https://hub.docker.com/> and install 'Docker Desktop' application.
2. Using the exising docker configuration file on project root, one can build the docker image of linux using the following command.
```sh
..\perl-csv-generator>docker build -t container-perl-csv .
```
This will create the ubuntu image and pull in the necessary dependencies perl, wget, pdftohtml. On console output one can see the execution logs of step by step execution of commands specified in the docker file.
```sh
FROM ubuntu:18.04
COPY . /perl-csv-generator
RUN apt-get update && apt-get install -y perl pdftohtml liblist-moreutils-perl libwww-perl wget
```
3. Launch the ubuntu image using the command below.
```sh
..\perl-csv-generator>docker run --interactive -v "C:\daily-work\perl-csv-generator\:/perl-csv-generator/" --tty container-perl-csv:latest bash
```
Note: The command also mount project root 'perl-csv-generator' on ubuntu image as an efficient approach to perform edits from host windows machine.
#### Trento
1. After successful launch, change to directory BusExtractTn.
```sh
root@d07a339c8c6b:/# cd perl-csv-generator/BusExtractTn
```
2. Peform clean
```sh
root@d07a339c8c6b:/# sh clean-tn.sh
```
3. Configure the script
