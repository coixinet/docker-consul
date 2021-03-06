# Use Ruby 2.3.6 as base image
FROM ruby:2.3.6

ENV DEBIAN_FRONTEND noninteractive

# Install essential Linux packages
RUN apt-get update -qq \
  && apt-get install -y --no-install-recommends \
    build-essential \
    imagemagick \
    libpq-dev \
    libxss1 \
    libappindicator1 \
    libindicator7 \
    nodejs \
    postgresql-client \
    sudo \
    unzip \
  && rm -r /var/lib/apt/lists/*


# Files created inside the container repect the ownership
RUN adduser --shell /bin/bash --disabled-password --gecos "" consul \
  && adduser consul sudo \
  && echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

RUN echo 'Defaults secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/local/bundle/bin"' > /etc/sudoers.d/secure_path
RUN chmod 0440 /etc/sudoers.d/secure_path

COPY consul/scripts/entrypoint.sh /usr/local/bin/entrypoint.sh

# Define where our application will live inside the image
ENV RAILS_ROOT /var/www/consul

# Create application home. App server will need the pids dir so just create everything in one shot
RUN mkdir -p $RAILS_ROOT/tmp/pids

# Set our working directory inside the image
WORKDIR $RAILS_ROOT

# Use the Gemfiles as Docker cache markers. Always bundle before copying app src.
# (the src likely changed and we don't want to invalidate Docker's cache too early)
# http://ilikestuffblog.com/2014/01/06/how-to-skip-bundle-install-when-deploying-a-rails-app-to-docker/
COPY consul/Gemfile* ./

# Prevent bundler warnings; ensure that the bundler version executed is >= that which created Gemfile.lock
RUN gem install bundler

# Finish establishing our Ruby environment
RUN bundle install --full-index

# Copy the Rails application into place
COPY consul .

# Ensure Delayed Job logs to STDOUT.
RUN sed -i -e 's/Logger\.new(.*)/Logger\.new(STDOUT)/' config/initializers/delayed_job_config.rb

# Copy any image overrides in
COPY images app/assets/images/custom/

# Compile assets. We're going to need a mock database.yml for the time being.
ARG RAILS_ENV=production
ARG ASSETS_PRECOMPILE=true
RUN cp config/database.yml.example config/database.yml \
      && rake assets:precompile \
      && rm -f config/database.yml

# Define the script we want run once the container boots
# Use the "exec" form of CMD so our script shuts down gracefully on SIGTERM (i.e. `docker stop`)
# CMD [ "config/containers/app_cmd.sh" ]
CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0"]
