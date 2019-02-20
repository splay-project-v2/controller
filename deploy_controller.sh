#!/bin/bash -
#===============================================================================
#
#          FILE: deploy_controller.sh
#
#         USAGE: ./deploy_controller.sh
#
#   DESCRIPTION:
#
#       OPTIONS: ---
#  REQUIREMENTS: ---
#          BUGS: ---
#         NOTES: ---
#        AUTHOR: Raziel Carvajal-Gomez (), raziel.carvajal@uclouvain.be
#  ORGANIZATION:
#       CREATED: 06/21/2018 15:24
#      REVISION:  ---
#===============================================================================

set -o nounset                              # Treat unset variables as an error

# The Database is now init by the backend
# ruby init_db.rb
# ruby init_users.rb

# Run suite of tests
# echo "Launch Unit Testing"
# ruby -Ilib:test ./tests/test_all.rb

echo "Init the lock"
ruby init_lock.rb
echo "Launch the Controller"
ruby controller.rb
