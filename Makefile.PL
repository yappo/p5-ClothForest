use inc::Module::Install;
name 'ClothForest';
all_from 'lib/ClothForest.pm';
#readme_from 'lib/ClothForest.pm';
#readme_markdown_from 'lib/ClothForest.pm';
githubmeta;

requires 'CloudForecast';
requires 'DBI';
requires 'Time::Piece';

tests 't/*.t';
author_tests 'xt';

build_requires 'Test::More';
auto_set_repository;
WriteAll;
