### Copyright 2017 Pixar

###
###    Licensed under the Apache License, Version 2.0 (the "Apache License")
###    with the following modification; you may not use this file except in
###    compliance with the Apache License and the following modification to it:
###    Section 6. Trademarks. is deleted and replaced with:
###
###    6. Trademarks. This License does not grant permission to use the trade
###       names, trademarks, service marks, or product names of the Licensor
###       and its affiliates, except as required to comply with Section 4(c) of
###       the License and to reproduce the content of the NOTICE file.
###
###    You may obtain a copy of the Apache License at
###
###        http://www.apache.org/licenses/LICENSE-2.0
###
###    Unless required by applicable law or agreed to in writing, software
###    distributed under the Apache License with the above modification is
###    distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
###    KIND, either express or implied. See the Apache License for the specific
###    language governing permissions and limitations under the Apache License.
###
###

module Chook

  # the server
  class Server < Sinatra::Base

    # helper module for authentication
    module Auth

      # an auth attempt with this user to this route
      # always fails, which resets the browser to prompt again
      LOG_OUT_USER = 'LOG_OUT'.freeze

      LOG_OUT_ROUTE = '/logout'.freeze

      # These two helpers let us decude which routes need
      # http basic auth and which don't
      #
      # To protect a route, put `protected!` as the
      # first line of code in the route.
      #
      # See http://sinatrarb.com/faq.html#auth
      #

      def protected!
        # don't protect if user isn't defined
        return unless Chook.config.webhooks_user

        return if authorized?
        headers['WWW-Authenticate'] = 'Basic realm="Restricted Area"'
        halt 401, "Not authorized\n"
      end

      def authorized?
        @auth ||= Rack::Auth::Basic::Request.new(request.env)

        # gotta have basic auth presented to us
        unless @auth.provided? && @auth.basic? && @auth.credentials
          Chook.logger.debug 'No basic auth provided on protected page'
          return false
        end

        # the logout user always gets false
        if @auth.credentials.first == Chook::Server::Auth::LOG_OUT_USER
          Chook.logger.debug "Logging out Basic Auth for IP: #{request.ip}"
          false

        # the webhooks user?
        elsif @auth.credentials.first == Chook.config.webhooks_user
          authenticate_webhooks_user @auth.credentials

        # a Jamf admin?
        elsif Chook.config.auth_via_jamf_server
          authenticate_jamf_admin @auth.credentials

        # we shouldn't be here
        else
          false
        end # if
      end # authorized?

      def authenticate_webhooks_user(creds)
        if creds.last == Chook::Server.webhooks_user_pw
          Chook.logger.debug "Got auth for webhooks user: #{Chook.config.webhooks_user}@#{request.ip}, route: #{request.path_info}"
          true
        else
          Chook.logger.warn "FAILED auth for webhooks user: #{Chook.config.webhooks_user}@#{request.ip}, route: #{request.path_info}"
          false
        end
      end # authenticate_webhooks_user

      def authenticate_jamf_admin(creds)
        require 'ruby-jss'
        JSS::APIConnection.new(
          user: creds.first,
          pw: creds.last,
          server: Chook.config.auth_via_jamf_server,
          port: Chook.config.jamf_port,
          use_ssl: Chook.config.jamf_use_ssl,
          verify_cert: Chook.config.jamf_verify_cert
        )
        Chook.logger.debug "Jamf Admin auth for: #{creds.first}@#{request.ip}, route: #{request.path_info}"
        true
      rescue JSS::AuthenticationError
        Chook.logger.warn "Jamf Admin auth FAILED for: #{creds.first}@#{request.ip}, route: #{request.path_info}"
        false
      end # authenticate_jamf_admin

    end # module auth

    helpers Chook::Server::Auth

  end # server

end # Chook

require 'chook/server/routes/home'
require 'chook/server/routes/handle_webhook_event'
require 'chook/server/routes/handlers'
require 'chook/server/routes/log'