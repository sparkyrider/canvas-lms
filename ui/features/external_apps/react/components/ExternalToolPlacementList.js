/*
 * Copyright (C) 2021 - present Instructure, Inc.
 *
 * This file is part of Canvas.
 *
 * Canvas is free software: you can redistribute it and/or modify it under
 * the terms of the GNU Affero General Public License as published by the Free
 * Software Foundation, version 3 of the License.
 *
 * Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
 * WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
 * A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
 * details.
 *
 * You should have received a copy of the GNU Affero General Public License along
 * with this program. If not, see <http://www.gnu.org/licenses/>.
 */

import I18n from 'i18n!external_tools'
import React from 'react'
import PropTypes from 'prop-types'
import store from '../lib/ExternalAppsStore'
import $ from '@canvas/rails-flash-notifications'
import {ToggleButton} from '@instructure/ui-buttons'
import {Text} from '@instructure/ui-text'
import {View} from '@instructure/ui-view'
import {Flex} from '@instructure/ui-flex'
import {IconCheckMarkSolid, IconEndSolid} from '@instructure/ui-icons'

export default class ExternalToolPlacementList extends React.Component {
  static propTypes = {
    tool: PropTypes.object.isRequired,
    onSuccess: PropTypes.func.isRequired
  }

  state = {
    tool: this.props.tool
  }

  /**
   * toggle the status of a given placement in the tool
   * cb will be called after state has been updated,
   * and can use this.state.tool
   * @param {String} placement required
   * @param {Function} cb optional
   */
  togglePlacement = (placement, cb = () => {}) => {
    this.setState(({tool}) => {
      tool[placement].enabled = !tool[placement].enabled
      return {tool}
    }, cb)
  }

  handleTogglePlacement = placement => {
    this.togglePlacement(placement, () => {
      store.togglePlacement({
        tool: this.state.tool,
        placement,
        onError: () => {
          $.flashError(I18n.t('Unable to toggle placement'))
          this.togglePlacement(placement)
        },
        onSuccess: r => {
          this.props.onSuccess(r, placement)
        }
      })
    })
  }

  placements = () => {
    const allPlacements = {
      account_navigation: I18n.t('Account Navigation'),
      assignment_edit: I18n.t('Assignment Edit'),
      assignment_selection: I18n.t('Assignment Selection'),
      assignment_view: I18n.t('Assignment View'),
      similarity_detection: I18n.t('Similarity Detection'),
      assignment_menu: I18n.t('Assignment Menu'),
      assignment_index_menu: I18n.t('Assignments Index Menu'),
      assignment_group_menu: I18n.t('Assignments Group Menu'),
      collaboration: I18n.t('Collaboration'),
      conference_selection: I18n.t('Conference Selection'),
      course_assignments_menu: I18n.t('Course Assignments Menu'),
      course_home_sub_navigation: I18n.t('Course Home Sub Navigation'),
      course_navigation: I18n.t('Course Navigation'),
      course_settings_sub_navigation: I18n.t('Course Settings Sub Navigation'),
      discussion_topic_menu: I18n.t('Discussion Topic Menu'),
      discussion_topic_index_menu: I18n.t('Discussions Index Menu'),
      editor_button: I18n.t('Editor Button'),
      file_menu: I18n.t('File Menu'),
      file_index_menu: I18n.t('Files Index Menu'),
      global_navigation: I18n.t('Global Navigation'),
      homework_submission: I18n.t('Homework Submission'),
      link_selection: I18n.t('Link Selection'),
      migration_selection: I18n.t('Migration Selection'),
      module_menu: I18n.t('Module Menu'),
      module_index_menu: I18n.t('Modules Index Menu'),
      module_group_menu: I18n.t('Modules Group Menu'),
      post_grades: I18n.t('Sync Grades'),
      quiz_menu: I18n.t('Quiz Menu'),
      quiz_index_menu: I18n.t('Quizzes Index Menu'),
      submission_type_selection: I18n.t('Submission Type Selection'),
      student_context_card: I18n.t('Student Context Card'),
      tool_configuration: I18n.t('Tool Configuration'),
      user_navigation: I18n.t('User Navigation'),
      wiki_page_menu: I18n.t('Page Menu'),
      wiki_index_menu: I18n.t('Pages Index Menu')
    }

    const tool = this.state.tool
    const appliedPlacements = Object.keys(allPlacements).filter(
      placement =>
        tool[placement] ||
        (tool.resource_selection && placement === 'assignment_selection') ||
        (tool.resource_selection && placement === 'link_selection')
    )
    if (appliedPlacements.length === 0) {
      return
    }

    // keep the old behavior of only displaying active placements when
    // toggles aren't present
    if (!this.shouldShowToggleButtons()) {
      return appliedPlacements
        .filter(key =>
          tool.resource_selection && (key === 'assignment_selection' || key === 'link_selection')
            ? tool.resource_selection.enabled
            : tool[key].enabled
        )
        .map(key => <div key={key}>{allPlacements[key]}</div>)
    }

    // temporary fix:
    // the `resource_selection` placment is deprecated, and will be removed.
    // the `assignment_selection` and `link_selection` placements together
    // serve the same purpose, so that's what is normally displayed. When
    // toggling placements, the tool still has only `resource_selection`,
    // so add and display that while hiding the "real" placements.
    // Goal: remove `resource_selection` entirely from the tool model,
    // then remove this code and the filter on `resource_selection` above.
    if (tool.resource_selection) {
      return [...appliedPlacements, 'resource_selection']
        .filter(key => key !== 'assignment_selection' && key !== 'link_selection')
        .map(key =>
          this.placementToggle(
            key,
            key === 'resource_selection'
              ? I18n.t('Assignment and Link Selection')
              : allPlacements[key],
            tool[key].enabled
          )
        )
    }

    return appliedPlacements.map(key =>
      this.placementToggle(key, allPlacements[key], tool[key].enabled)
    )
  }

  shouldShowToggleButtons = () => {
    const tool = this.state.tool
    const is_1_1_tool = tool.version === '1.1'
    const canUpdateTool = ENV.PERMISSIONS && ENV.PERMISSIONS.create_tool_manually
    const isEditableContext =
      ENV.CONTEXT_BASE_URL &&
      tool.context &&
      ENV.CONTEXT_BASE_URL.includes(tool.context.toLowerCase())

    return is_1_1_tool && canUpdateTool && isEditableContext
  }

  placementToggle = (key, value, enabled) => {
    const props = enabled
      ? {
          status: 'unpressed',
          color: 'success',
          renderIcon: IconCheckMarkSolid,
          screenReaderLabel: I18n.t('Placement active; click to deactivate'),
          renderTooltipContent: I18n.t('Active')
        }
      : {
          status: 'pressed',
          color: 'secondary',
          renderIcon: IconEndSolid,
          screenReaderLabel: I18n.t('Placement inactive; click to activate'),
          renderTooltipContent: I18n.t('Inactive')
        }

    return (
      <Flex justifyItems="space-between" key={key}>
        <Flex.Item>{value}</Flex.Item>
        <Flex.Item>
          <ToggleButton
            status={props.status}
            color={props.color}
            renderIcon={props.renderIcon}
            screenReaderLabel={props.screenReaderLabel}
            renderTooltipContent={props.renderTooltipContent}
            onClick={() => this.handleTogglePlacement(key)}
          />
        </Flex.Item>
      </Flex>
    )
  }

  render = () => {
    const placements = this.placements()

    if (!placements || placements.length === 0) {
      return I18n.t('No Placements Enabled')
    }

    if (!this.shouldShowToggleButtons()) {
      return placements
    }

    return (
      <>
        {placements}
        <View
          display="inline-block"
          padding="none small"
          margin="small none"
          borderWidth="none none none large"
          borderColor="info"
          maxWidth="24rem"
        >
          <Text size="small" lineHeight="condensed">
            <p style={{margin: 0}}>
              {I18n.t(
                'It may take some time for placement availability to reflect any changes made here. ' +
                  'You can also clear your cache and hard refresh on pages where you expect placements to change.'
              )}
            </p>
          </Text>
        </View>
      </>
    )
  }
}
