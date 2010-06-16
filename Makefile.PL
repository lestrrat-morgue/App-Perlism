use inc::Module::Install;

name 'App-Perlism';

requires 'Cache::Memcached::Fast';
requires 'Crypt::SSLeay'; # for https
requires 'Encode';
requires 'MooseX::SimpleConfig';
requires 'Net::Twitter', 3;
requires 'Net::Oauth', 0.26;

WriteAll;