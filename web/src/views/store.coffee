import { ref, computed } from "vue"
import default_git_actions from './default-git-actions.json'
import { parse } from "./log-utils.coffee"
import { git, get_config, exchange_message, add_push_listener } from "../bridge.coffee"
import { parse_config_actions } from "./GitInput.coffee"
import GitInputModel from './GitInput.coffee'
``###*
# @typedef {import('./types').GitRef} GitRef
# @typedef {import('./types').Branch} Branch
# @typedef {import('./types').Vis} Vis
# @typedef {import('./types').Commit} Commit
# @typedef {import('./types').ConfigGitAction} ConfigGitAction
# @typedef {import('./types').GitAction} GitAction
###
###* @template T @typedef {import('vue').Ref<T>} Ref ###
###* @template T @typedef {import('vue').ComputedRef<T>} ComputedRef ###

#########################
# This file should be used for state that is of importance for more than just one component.
# It encompasses state, actions and getters (computed values).
#########################

``###* @type {Ref<Commit[]|null>} ###
export commits = ref null

``###* @type {Ref<Branch[]>} ###
export branches = ref []
# this is either a branch id(name) or HEAD in which case it will simply not be shown
# which is also not necessary because HEAD is then also visible as a branch tip.
export head_branch = ref ''
export vis_max_length = ref 0
export git_status = ref ''
###* @type {Ref<string|null>} ###
export default_origin = ref ''

export git_run_log = (###* @type string ### log_args) =>
	sep = '^%^%^%^%^'
	log_args = log_args.replace(" --pretty={EXT_FORMAT}", " --pretty=format:\"#{sep}%h#{sep}%an#{sep}%ae#{sep}%at#{sep}%D#{sep}%s\"")
	stash_refs = try await git 'reflog show --format="%h" stash' catch then ""
	log_args = log_args.replace("{STASH_REFS}", stash_refs.replaceAll('\n', ' '))
	# errors will be handled by GitInput
	[ log_data, branch_data, stash_data, status_data, head_data ] = await Promise.all [
		git log_args
		git "branch --list --all --format=\"%(upstream:remotename)#{sep}%(refname)\""
		try await git "stash list --format=\"%h %gd\""
		git 'status'
		git 'rev-parse --abbrev-ref HEAD'
	]
	return if not log_data?
	parsed = parse log_data, branch_data, stash_data, sep
	commits.value = parsed.commits
	branches.value = parsed.branches
	# todo rename to vis_max_amount
	vis_max_length.value = parsed.vis_max_length
	head_branch.value = head_data
	git_status.value = status_data
	likely_default_branch = (branches.value.find (b) => b.name=='master'||b.name=='main') || branches.value[0]
	default_origin.value = likely_default_branch?.remote_name or likely_default_branch?.tracking_remote_name or null
``###* @type {Ref<Ref<GitInputModel|null>|null>} ###
export main_view_git_input_ref = ref null
export refresh_main_view = =>
	console.warn('refreshing main view')
	main_view_git_input_ref.value?.value?.execute()

export update_commit_stats = (###* @type {Commit[]} ### commits) =>
	data = await git "show --format=\"%h\" --shortstat " + commits.map((c)=>c.hash).join(' ')
	return if not data
	hash = ''
	for line from data.split('\n').filter(Boolean)
		if not line.startsWith ' '
			hash = line
			continue
		stat = files_changed: 0, insertions: 0, deletions: 0
		#  3 files changed, 87 insertions(+), 70 deletions(-)
		for stmt from line.trim().split(', ')
			words = stmt.split(' ')
			if words[1].startsWith 'file'
				stat.files_changed = Number(words[0])
			else if words[1].startsWith 'insertion'
				stat.insertions = Number(words[0])
			else if words[1].startsWith 'deletion'
				stat.deletions = Number(words[0])
		commits[commits.findIndex((cp)=>cp.hash==hash)].stats = stat

``###* @type {Ref<ConfigGitAction[]>} ###
export global_actions = ref []
``###* @type {Ref<ConfigGitAction[]>} ###
config_branch_actions = ref []
``###* @type {Ref<ConfigGitAction[]>} ###
config_tag_actions = ref []
``###* @type {Ref<ConfigGitAction[]>} ###
config_commit_actions = ref []
``###* @type {Ref<ConfigGitAction[]>} ###
config_commits_actions = ref []
export commit_actions = (###* @type string ### hash) => computed =>
	parse_config_actions(config_commit_actions.value, [['{COMMIT_HASH}', hash]])
export commits_actions = (###* @type string[] ### hashes) => computed =>
	parse_config_actions(config_commits_actions.value, [['{COMMIT_HASHES}', hashes.join(' ')]])
export branch_actions = (###* @type Branch ### branch) => computed =>
	parse_config_actions(config_branch_actions.value, [
		['{BRANCH_NAME}', branch.id]
		['{LOCAL_BRANCH_NAME}', branch.name]
		['{REMOTE_NAME}', branch.remote_name or branch.tracking_remote_name or default_origin.value or 'MISSING_REMOTE_NAME']])
export tag_actions = (###* @type string ### tag_name) => computed =>
	parse_config_actions(config_tag_actions.value, [['{TAG_NAME}', tag_name]])
``###* @type {Ref<ConfigGitAction[]>} ###
config_stash_actions = ref []
export stash_actions = (###* @type string ### stash_name) => computed =>
	parse_config_actions(config_stash_actions.value, [['{STASH_NAME}', stash_name]])
``###* @type {Ref<ConfigGitAction[]>} ###
_unparsed_combine_branches_actions = ref []
export combine_branches_actions = computed =>
	parse_config_actions(_unparsed_combine_branches_actions.value, [
		['{SOURCE_BRANCH_NAME}', combine_branches_from_branch_name.value]
		['{TARGET_BRANCH_NAME}', combine_branches_to_branch_name.value]])

export combine_branches_to_branch_name = ref ''
export combine_branches_from_branch_name = ref ''
export combine_branches = (###* @type string ### from_branch_name, ###* @type string ### to_branch_name) =>
	return if from_branch_name == to_branch_name
	combine_branches_to_branch_name.value = to_branch_name
	combine_branches_from_branch_name.value = from_branch_name

``###* @type {Ref<GitAction|null>} ###
export selected_git_action = ref null

``###* @type {Ref<number|string>} ###
export config_width = ref ''

``###* @type {Ref<boolean>} ###
export config_scroll_snapping_active = ref false

``###* @type {Ref<boolean>} ###
export config_show_quick_branch_tips = ref false

export config_branch_visualization_type = ref 'svg'

###* @type {Ref<string[]>} ###
export repo_names = ref []

export init = =>
	refresh_config()

	repo_names.value = await exchange_message 'get-repo-names'
	add_push_listener 'repo-names-change', ({ data: names }) =>
		repo_names.value = names

	add_push_listener 'config-change', =>
		refresh_config()
		refresh_main_view()
	
	add_push_listener 'repo-external-state-change', refresh_main_view
export refresh_config = =>
	# TODO change to single request get_config and then use e.g. config.actions.global or at least config['actions.global'], branch-width etc
	global_actions.value = default_git_actions['actions.global'].concat(await get_config 'actions.global')
	config_branch_actions.value = default_git_actions['actions.branch'].concat(await get_config 'actions.branch')
	config_commit_actions.value = default_git_actions['actions.commit'].concat(await get_config 'actions.commit')
	config_commits_actions.value = default_git_actions['actions.commits'].concat(await get_config 'actions.commits')
	config_stash_actions.value = default_git_actions['actions.stash'].concat(await get_config 'actions.stash')
	config_tag_actions.value = default_git_actions['actions.tag'].concat(await get_config 'actions.tag')
	_unparsed_combine_branches_actions.value = default_git_actions['actions.branch-drop'].concat(await get_config 'actions.branch-drop')

	config_width.value = await get_config 'branch-width'

	config_scroll_snapping_active.value = ! (await get_config 'disable-scroll-snapping')

	config_show_quick_branch_tips.value = ! (await get_config 'hide-quick-branch-tips')

	config_branch_visualization_type.value = await get_config 'branch-visualization'

export vis_v_width = computed =>
	if not config_width.value or not Number(config_width.value)
		# Linear drop from 10 to 2
		Math.max(2, Math.min(10, Math.round(vis_max_length.value * (-1) * 8 / 50 + 18)))
	else
		Number(config_width.value)