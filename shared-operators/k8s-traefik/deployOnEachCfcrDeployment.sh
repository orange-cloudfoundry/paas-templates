#!/bin/sh
deploy=k8s-traefik
cd ././../../micro-depls/${deploy}/template/tools/
sh ./add-symlink.sh
pwd
cd ../../../../shared-operators/${deploy}/



cd ././../../master-depls/${deploy}/template/tools/
sh ./add-symlink.sh
pwd
cd ../../../../shared-operators/${deploy}/

cd ././../../coab-depls/10-${deploy}/template/tools/
sh ./add-symlink.sh
pwd
cd ../../../../shared-operators/${deploy}/
