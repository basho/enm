#!/bin/sh
[ `basename $PWD` != "c_src" ] && cd ./c_src
exec make "$@"
