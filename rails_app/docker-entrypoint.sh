#!/bin/bash

set -e

echo "Environment: $RAILS_ENV"
if [ -f "$APP_PATH/Gemfile"  ]
then
    echo "Gemfile check sucess"
else
    echo "generate Gemfile!"
    echo "source 'https://rubygems.org'" | tee $APP_PATH/Gemfile
    echo "gem 'rails', '~> 6.1.4'" >> $APP_PATH/Gemfile
    bundle install --jobs 20 --retry 5    
    bundle exec rails new $APP_PATH -f -d $DB_ADAPTER
fi





# install missing gems
bundle check || bundle install --jobs 20 --retry 5

# Remove pre-existing puma/passenger server.pid
rm -f $APP_PATH/tmp/pids/green.pid
rm -f $APP_PATH/tmp/pids/blue.pid
echo "start rails app"
# run passed commands
bundle exec ${@}