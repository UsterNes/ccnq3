#!/usr/bin/env bash

coffee -c js/*.coffee
cat js/jquery.js          \
    js/jquery-ui.js       \
    js/jquery.validate.js \
    js/jquery.couch.js    \
    js/jquery.deepjson.js \
    js/sammy.js           \
    js/sammy.title.js     \
    js/sammy.couch.js     \
    js/coffeekup.js       \
    js/forms.js           \
    js/jquery.smartWizard-2.0.js \
  > js/default.js