<template lang="slm">
.commit-details
	h2.summary :title="commit.subject" {{ commit.subject }}

	p.body {{ body }}

	h3 Refs related to the commit
	template v-if="config_show_buttons"
		.stash v-if="stash"
			h3 Stash:
			.row.gap-5.wrap
				git-action-button v-for="action of stash_actions" :git_action="action"

		.branch-tips v-if="branch_tips.length"
			ul v-for="branch_tip of branch_tips"
				li
					ref-tip :git_ref="branch_tip" :commit="commit"
					.row.gap-5.wrap
						git-action-button v-for="action of branch_actions(branch_tip)" :git_action="action"

		.tags v-if="tags.length"
			ul v-for="tag, tag_i of tags"
				li
					ref-tip :git_ref="tag" :commit="commit"
					pre {{ tag_details[tag_i] }}
					.row.gap-5.wrap
						git-action-button v-for="action of tag_actions(tag.name)" :git_action="action"

		.commit
			h3 style="word-break: break-all;"
				| This commit
				br
				button style="margin-right: 3px;" @click="$emit('hash_clicked',commit.full_hash)" title="Jump to commit"
					i.codicon.codicon-link
				| {{ commit.full_hash }}
				| :
			.row.gap-5.wrap
				git-action-button v-for="action of commit_actions" :git_action="action"

	h3 Parent commits
	ul
		li v-for="parent_hash of parent_hashes" style="word-break: break-all;"
			button style="margin-right: 3px;" @click="$emit('hash_clicked',parent_hash)" title="Jump to commit"
				i.codicon.codicon-link
			| {{ parent_hash }}

	files-diffs-list :files="changed_files" @show_diff="show_diff" @view_rev="view_rev"

	br
	details
		summary.align-center Compare...
		| In order to compare this commit with another one, do <kbd>Ctrl</kbd>+Click on any other commit in the main view

	h3 Contained in branches
	div.contained-in-branch v-for="branch of contained_in_branches"
		| {{ branch }}

</template>

<script lang="coffee" src="./CommitDetails.coffee"></script>

<style lang="stylus" scoped>
h2.summary
	white-space pre-line
	word-break break-word
	overflow hidden
	text-overflow ellipsis
.body
	white-space pre-wrap
	word-break break-word
.branch-tips, .tags
	.ref-tip
		margin 20px 10px 10px

.contained-in-branch
	margin 3px 5px 3px 5px
	background #000
	display inline-block
	padding 1px 3px
	border 1px solid #505050
	border-radius 7px
	white-space pre

</style>