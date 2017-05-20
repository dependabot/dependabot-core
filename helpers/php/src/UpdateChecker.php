<?php

class UpdateChecker
{
  public function get_latest_resolvable_version()
  {
    // TODO: Write real codes
    //
    // Note: if any pre-processing of the dependency files is necessary, it
    // can be done in Ruby pretty easily (e.g., UpdateCheckers::Ruby removes
    // the version specification from the Gemfile before opening up Bundler).
    fwrite(STDOUT, "{\"error\": \"Function not implemented!\" }");
    exit(1);
  }
}

?>
