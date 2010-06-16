use inc::Module::Install;

name 'App-Perlism';

requires 'Crypt::SSLeay'; # for https
requires 'Encode';
requires 'Net::Twitter', 3;

WriteAll;