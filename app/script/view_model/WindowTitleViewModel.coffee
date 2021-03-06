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

window.z ?= {}
z.ViewModel ?= {}

class z.ViewModel.WindowTitleViewModel
  constructor: (@content, @user_repository, @conversation_repository) ->
    @logger = new z.util.Logger 'z.ViewModel.WindowTitleViewModel', z.config.LOGGER.OPTIONS
    amplify.subscribe z.event.WebApp.LOADED, @initiate_title_updates

  initiate_title_updates: =>
    @logger.log @logger.levels.INFO, 'Starting to update window title'
    ko.computed =>

      window_title = ''
      badge_count = 0
      number_of_unread_conversations = 0
      number_of_connect_requests = @user_repository.connect_requests().length

      @conversation_repository.conversations_unarchived().forEach (conversation_et) ->
        if conversation_et.type() isnt z.conversation.ConversationType.CONNECT
          number_of_unread_conversations++ if conversation_et.number_of_unread_messages() > 0

      badge_count = number_of_connect_requests + number_of_unread_conversations

      if badge_count > 0
        window_title += "(#{badge_count}) "

      amplify.publish z.event.WebApp.CONVERSATION.UNREAD, badge_count

      switch @content.state()
        when z.ViewModel.CONTENT_STATE.PENDING
          if number_of_connect_requests > 1
            window_title += z.localization.Localizer.get_text {
              id: z.string.conversation_list_many_connection_request
              replace: {placeholder: '%no', content: number_of_connect_requests}
            }
          else
            window_title += z.localization.Localizer.get_text z.string.conversation_list_one_connection_request
        when z.ViewModel.CONTENT_STATE.CONVERSATION
          window_title += @conversation_repository.active_conversation()?.display_name()
        when z.ViewModel.CONTENT_STATE.PROFILE
          window_title += @user_repository.self().name()

      if window_title is ''
        window_title = z.localization.Localizer.get_text z.string.wire
      else
        window_title += " - #{z.localization.Localizer.get_text z.string.wire}"

      window.document.title = window_title

    .extend rateLimit: 750
