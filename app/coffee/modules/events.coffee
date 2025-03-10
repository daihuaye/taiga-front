###
# Copyright (C) 2014-2015 Andrey Antukh <niwi@niwi.be>
# Copyright (C) 2014-2015 Jesús Espino Garcia <jespinog@gmail.com>
# Copyright (C) 2014-2015 David Barragán Merino <bameda@dbarragan.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.
#
# File: modules/events.coffee
###

taiga = @.taiga
startswith = @.taiga.startswith
bindMethods = @.taiga.bindMethods

module = angular.module("taigaEvents", [])


class EventsService
    constructor: (@win, @log, @config, @auth) ->
        bindMethods(@)

    initialize: (sessionId) ->
        @.sessionId = sessionId
        @.subscriptions = {}
        @.connected = false
        @.error = false
        @.pendingMessages = []

        @.missedHeartbeats = 0
        @.heartbeatInterval = null

        if @win.WebSocket is undefined
            @log.info "WebSockets not supported on your browser"

    setupConnection: ->
        @.stopExistingConnection()

        url = @config.get("eventsUrl")

        # This allows disable events in case
        # url is not found on the configuration.
        return if not url

        # This allows relative urls in configuration.
        if not startswith(url, "ws:") and not startswith(url, "wss:")
            loc = @win.location
            scheme = if loc.protocol == "https:" then "wss:" else "ws:"
            path = _.str.ltrim(url, "/")
            url = "#{scheme}//#{loc.host}/#{path}"

        @.ws = new @win.WebSocket(url)
        @.ws.addEventListener("open", @.onOpen)
        @.ws.addEventListener("message", @.onMessage)
        @.ws.addEventListener("error", @.onError)
        @.ws.addEventListener("close", @.onClose)

    stopExistingConnection: ->
        if @.ws is undefined
            return

        @.ws.removeEventListener("open", @.onOpen)
        @.ws.removeEventListener("close", @.onClose)
        @.ws.removeEventListener("error", @.onError)
        @.ws.removeEventListener("message", @.onMessage)
        @.stopHeartBeatMessages()
        @.ws.close()

        delete @.ws

    ###########################################
    # Heartbeat (Ping - Pong)
    ###########################################
    # See  RFC https://tools.ietf.org/html/rfc6455#section-5.5.2
    #      RFC https://tools.ietf.org/html/rfc6455#section-5.5.3
    startHeartBeatMessages: ->
        return if @.heartbeatInterval

        maxMissedHeartbeats =  @config.get("eventsMaxMissedHeartbeats", 5)
        heartbeatIntervalTime = @config.get("eventsHeartbeatIntervalTime", 60000)

        @.missedHeartbeats = 0
        @.heartbeatInterval = setInterval(() =>
            try
                if @.missedHeartbeats >= maxMissedHeartbeats
                    throw new Error("Too many missed heartbeats PINGs.")

                @.missedHeartbeats++
                @.sendMessage({cmd: "ping"})
                @log.debug("HeartBeat send PING")
            catch e
                @log.error("HeartBeat error: " + e.message)
                @.stopHeartBeatMessages()
        , heartbeatIntervalTime)

        @log.debug("HeartBeat enabled")

    stopHeartBeatMessages: ->
        return if not @.heartbeatInterval

        clearInterval(@.heartbeatInterval)
        @.heartbeatInterval = null

        @log.debug("HeartBeat disabled")

    processHeartBeatPongMessage: (data) ->
        @.missedHeartbeats = 0
        @log.debug("HeartBeat recived PONG")

    ###########################################
    # Messages
    ###########################################
    serialize: (message) ->
        if _.isObject(message)
            return JSON.stringify(message)
        return message

    sendMessage: (message) ->
        @.pendingMessages.push(message)

        if not @.connected
            return

        messages = _.map(@.pendingMessages, @.serialize)
        @.pendingMessages = []

        for msg in messages
            @.ws.send(msg)

    processMessage: (data) =>
        routingKey = data.routing_key

        if not @.subscriptions[routingKey]?
            return

        subscription = @.subscriptions[routingKey]
        subscription.scope.$apply ->
            subscription.callback(data.data)

    ###########################################
    # Subscribe and Unsubscribe
    ###########################################
    subscribe: (scope, routingKey, callback) ->
        if @.error
            return

        @log.debug("Subscribe to: #{routingKey}")
        subscription = {
            scope: scope,
            routingKey: routingKey,
            callback: _.debounce(callback, 500, {"leading": true, "trailing": false})
        }

        message = {
            "cmd": "subscribe",
            "routing_key": routingKey
        }

        @.subscriptions[routingKey] = subscription
        @.sendMessage(message)
        scope.$on("$destroy", => @.unsubscribe(routingKey))

    unsubscribe: (routingKey) ->
        if @.error
            return

        @log.debug("Unsubscribe from: #{routingKey}")

        message = {
            "cmd": "unsubscribe",
            "routing_key": routingKey
        }

        @.sendMessage(message)

    ###########################################
    # Event listeners
    ###########################################
    onOpen: ->
        @.connected = true
        @.startHeartBeatMessages()

        @log.debug("WebSocket connection opened")
        token = @auth.getToken()

        message = {
            cmd: "auth"
            data: {token: token, sessionId: @.sessionId}
        }

        @.sendMessage(message)

    onMessage: (event) ->
        @.log.debug "WebSocket message received: #{event.data}"

        data = JSON.parse(event.data)
        if data.cmd == "pong"
            @.processHeartBeatPongMessage(data)
        else
            @.processMessage(data)

    onError: (error) ->
        @log.error("WebSocket error: #{error}")
        @.error = true

    onClose: ->
        @log.debug("WebSocket closed.")
        @.connected = false
        @.stopHeartBeatMessages()


class EventsProvider
    setSessionId: (sessionId) ->
        @.sessionId = sessionId

    $get: ($win, $log, $conf, $auth) ->
        service = new EventsService($win, $log, $conf, $auth)
        service.initialize(@.sessionId)
        return service

    @.prototype.$get.$inject = ["$window", "$log", "$tgConfig", "$tgAuth"]

module.provider("$tgEvents", EventsProvider)
