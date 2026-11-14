--!nonstrict
--[[
	BUMP's UI Labs storybook: the style board. Open the UI Labs plugin in Studio and it lists the
	stories under Client/UIFusion/Stories:

	    Tokens   the colours, type, plates and shapes everything is made of
	    Kit      every piece of the kit, in every state
	    HUD      the whole HUD, playing against a fake round

	Each has a Backdrop control to judge the plates against bright and dark scenes.
]]

return {
	name = "BUMP",
	storyRoots = {
		script.Parent.Parent:WaitForChild("Stories"),
	},
}
