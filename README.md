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
1. In order to generate CSVs for Trento Urban timetables, change to directory BusExtractTn.
```sh
root@d07a339c8c6b:/# cd perl-csv-generator/BusExtractTn
```
2. Peform clean
```sh
root@d07a339c8c6b:/# sh clean-tn.sh
```
3. Open extract-tn.pl script on project root and configure properties.
```sh
my @routes = ('01_A','01_R','02_C','03_A','03_R','04_A','04_R','05_A','05_R','05_b','06_A','06_R','07_A','07_R','08_A','08_R','09_A','09_R','10_A','10_R','11_A','11_R',
              '12_A','12_R','13_A','13_R','14_A','14_R','15_A','15_R','16_A','16_R','17_A','17_R','NP_C','%20A_C','%20B_C','%20C_A','%20C_R','%20G_A','%20G_R','CM_A','CM_R');

my @routes_feriale = @routes;

my @routes_festivo = ('01_A','01_R','02_C','03_A','03_R','04_A','04_R','05_A','05_R',    '06_A','06_R',              '08_A','08_R',              '10_A','10_R',              
              '12_A','12_R',                                                        '17_A','17_R',       '%20A_C');

my $BASE_TTE_URL = "https://www.trentinotrasporti.it/pdforari/urbani/linee";
my $BASE_TTE_NAME = "OrariDiDirettrice-T18I-T-";
```

| Property | Description |
| ------ | ------ |
| BASE_TTE_URL | The URL of TrentinoTrasport website URL |
| BASE_TTE_NAME | The common sarting prefix of PDF files |
| routes | Array specifying route name of buses, contains short name of all the bus lines whose timetables are provided on BASE_TTE_URL url. Any new addition to bus service must be added in this variable |

4. Run the script.
```sh
root@d07a339c8c6b:/# cd perl-csv-generator/BusExtractTn
```

