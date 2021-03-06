#
# Wire
# Copyright (C) 2016 Wire Swiss GmbH
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see http://www.gnu.org/licenses/.
#

# grunt test_init && grunt test_run:event/EventRepository

describe 'Event Repository', ->
  test_factory = new TestFactory()
  last_notification_id = undefined

  websocket_service_mock = do ->
    websocket_handler = null

    connect: (handler) ->
      websocket_handler = handler

    publish: (payload) ->
      websocket_handler payload

  beforeEach (done) ->
    test_factory.exposeEventActors()
    .then (event_repository) ->
      event_repository.web_socket_service = websocket_service_mock
      notification_service.get_notifications = ->
        return new Promise (resolve) ->
          window.setTimeout ->
            resolve {
              has_more: false
              notifications: [
                {id: z.util.create_random_uuid(), payload: []}
                {id: z.util.create_random_uuid(), payload: []}
              ]
            }
          , 10

      notification_service.get_last_notification_id_from_db = ->
        if last_notification_id
          Promise.resolve last_notification_id
        else
          Promise.reject new z.event.EventError 'ID not found in storage', z.event.EventError::TYPE.DATABASE_NOT_FOUND

      notification_service.save_last_notification_id_to_db = ->
        Promise.resolve z.event.NotificationService::PRIMARY_KEY_LAST_NOTIFICATION

      last_notification_id = undefined
      done()
    .catch done.fail

  describe 'update_from_notification_stream', ->

    beforeEach ->
      spyOn(cryptography_repository, 'save_encrypted_event')
      spyOn(event_repository, '_handle_notification').and.callThrough()
      spyOn(event_repository, '_buffer_web_socket_notification').and.callThrough()
      spyOn(event_repository, '_handle_buffered_notifications').and.callThrough()
      spyOn(event_repository, '_handle_event')
      spyOn(event_repository, '_distribute_event')
      spyOn(notification_service, 'get_notifications').and.callThrough()
      spyOn(notification_service, 'get_last_notification_id_from_db').and.callThrough()

    it 'should skip fetching notifications if last notification ID not found in storage', (done) ->
      event_repository.connect()
      event_repository.update_from_notification_stream()
      .then ->
        expect(notification_service.get_last_notification_id_from_db).toHaveBeenCalled()
        expect(notification_service.get_notifications).not.toHaveBeenCalled()
        done()
      .catch done.fail

    it 'should buffer notifications when notification stream is not processed', ->
      last_notification_id = z.util.create_random_uuid()
      event_repository.connect()
      websocket_service_mock.publish {id: z.util.create_random_uuid(), payload: []}
      expect(event_repository._buffer_web_socket_notification).toHaveBeenCalled()
      expect(event_repository._handle_notification).not.toHaveBeenCalled()
      expect(event_repository.can_handle_web_socket()).toBeFalsy()
      expect(event_repository.web_socket_buffer.length).toBe 1

    it 'should handle buffered notifications after notifications stream was processed', (done) ->
      last_notification_id = z.util.create_random_uuid()
      last_published_notification_id = z.util.create_random_uuid()
      event_repository.last_notification_id last_notification_id
      event_repository.connect()
      websocket_service_mock.publish {id: z.util.create_random_uuid(), payload: []}

      websocket_service_mock.publish {id: last_published_notification_id, payload: []}
      event_repository.update_from_notification_stream()
      .then () ->
        expect(event_repository._handle_buffered_notifications).toHaveBeenCalled()
        expect(event_repository.web_socket_buffer.length).toBe 0
        expect(event_repository.last_notification_id()).toBe last_published_notification_id
        expect(event_repository.can_handle_web_socket()).toBeTruthy()
        done()
      .catch done.fail

  describe '_handle_event', ->

    beforeEach ->
      spyOn(cryptography_repository, 'save_encrypted_event').and.returnValue Promise.resolve(mapped: 'dummy content')
      spyOn(cryptography_repository, 'save_unencrypted_event').and.returnValue Promise.resolve(mapped: 'dummy content')
      spyOn(event_repository, '_distribute_event')

    it 'should not save but distribute user events', (done) ->
      event_repository._handle_event {type: z.event.Backend.USER.UPDATE}, z.event.EventRepository::NOTIFICATION_SOURCE.SOCKET
      .then ->
        expect(cryptography_repository.save_encrypted_event).not.toHaveBeenCalled()
        expect(cryptography_repository.save_unencrypted_event).not.toHaveBeenCalled()
        expect(event_repository._distribute_event).toHaveBeenCalled()
        done()
      .catch done.fail

    it 'should not save but distribute call events', (done) ->
      event_repository._handle_event {type: z.event.Backend.CALL.FLOW_ACTIVE}, z.event.EventRepository::NOTIFICATION_SOURCE.SOCKET
      .then ->
        expect(cryptography_repository.save_encrypted_event).not.toHaveBeenCalled()
        expect(cryptography_repository.save_unencrypted_event).not.toHaveBeenCalled()
        expect(event_repository._distribute_event).toHaveBeenCalled()
        done()
      .catch done.fail

    it 'should not save but distribute conversation.create event', (done) ->
      event_repository._handle_event {type: z.event.Backend.CONVERSATION.CREATE}, z.event.EventRepository::NOTIFICATION_SOURCE.SOCKET
      .then ->
        expect(cryptography_repository.save_encrypted_event).not.toHaveBeenCalled()
        expect(cryptography_repository.save_unencrypted_event).not.toHaveBeenCalled()
        expect(event_repository._distribute_event).toHaveBeenCalled()
        done()
      .catch done.fail

    it 'should save and distribute conversation.message-add event', (done) ->
      event_repository._handle_event {type: z.event.Backend.CONVERSATION.MESSAGE_ADD}, z.event.EventRepository::NOTIFICATION_SOURCE.SOCKET
      .then ->
        expect(cryptography_repository.save_encrypted_event).not.toHaveBeenCalled()
        expect(cryptography_repository.save_unencrypted_event).toHaveBeenCalled()
        expect(event_repository._distribute_event).toHaveBeenCalled()
        done()
      .catch done.fail
