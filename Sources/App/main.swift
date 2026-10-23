import SwiftUI

if CommandLine.arguments.dropFirst().first == RootHelperTool.launchArgument {
	RootHelperTool.run(Array(CommandLine.arguments.dropFirst(2)))
}

FilzerApp.main()
