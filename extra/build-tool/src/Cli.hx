import mcli.*;
import sys.FileSystem.*;
import haxe.io.Path;
import haxe.Resource;
import unihx.pvt.compiler.*;

using StringTools;

class Cli extends CommandLine
{
	/**
		Show this message.
	**/
	public function help()
	{
		Sys.println(this.showUsage());
		Sys.exit(0);
	}

	private function err(msg:String)
	{
		Sys.stderr().writeString(msg + "\n");
		Sys.exit(1);
	}

	private function callHaxe(args:Array<String>)
	{
		print( 'haxe ' + [for (arg in args) arg.split('"').join('\\\"') ].join(" ") );
		var ret = Sys.command('haxe', args);
		if (ret != 0)
			Sys.exit(ret);
	}

	private function deleteAll(dir:String)
	{
		for (f in readDirectory(dir))
		{
			if (isDirectory('$dir/$f'))
			{
				deleteAll('$dir/$f');
			} else {
				deleteFile('$dir/$f');
			}
		}
		deleteDirectory(dir);
	}

	private function copy(file:String, to:String)
	{
		sys.io.File.saveBytes(to, sys.io.File.getBytes(file));
	}

	/**
		Force always to yes
	**/
	public var force:Bool = false;

	public var verbose:Bool = false;

	private function print(msg:String)
	{
		if (verbose) Sys.println(msg);
	}

	private function ask(msg:String, ?preSelect:Bool):Bool
	{
		if (force) return true;
		Sys.println(msg);
		var stdin = Sys.stdin();
		var str = "(" + (preSelect == true ? "Y" : "y") + "/" + (preSelect == false ? "N" : "n") + ") ";
		while (true)
		{
			Sys.print(str);
			var ln = stdin.readLine().trim().toLowerCase();
			if (ln == "" && preSelect != null)
				return preSelect;
			else if (ln == "y")
				return true;
			else if (ln == "n")
				return false;
		}
	}

	public static function main()
	{
		var args = Sys.args();
		if (Sys.getEnv('HAXELIB_RUN') == "1")
		{
			unihxPath = Sys.getCwd();
			var curpath = args.pop();
			Sys.setCwd(curpath);
		}
		new mcli.Dispatch(args).dispatch(new Helper());
	}

	private static var unihxPath:String = null;
	private function getUnihxPath():String
	{
		if (unihxPath != null)
			return unihxPath;
		var p = new sys.io.Process('haxelib',['path','unihx']);
		try
		{
			while(true)
			{
				var ln = p.stdout.readLine().trim();
				if (ln.charCodeAt(0) != '-'.code && ln.indexOf('/src') >= 0 && exists(ln.substr(0,ln.length-1)))
				{
					unihxPath = ln.substr(0,ln.indexOf('/src'));
					break;
				}
			}
		}
		catch(e:haxe.io.Eof)
		{
		}
		if (p.exitCode() != 0 || unihxPath == null)
		{
			err('Cannot determine the path of the "unihx" project. Make sure haxelib is installed correctly, and unihx is installed through haxelib');
		}

		return unihxPath;
	}
}

/**
	unihx helper tool
**/
class Helper extends CommandLine
{
	/**
		Initializes the target Unity project to use unihx
	**/
	public function init(d:Dispatch)
	{
		d.dispatch(new InitCmd());
	}

}

/**
	unihx init [target-dir] : initializes the target Unity project to use unihx.
**/
class InitCmd extends Cli
{
	private function checkProjectUpdate(assets:String)
	{
		if (exists(assets + "/hx-compiled") || exists(assets + "/Standard Assets/Haxe-Std"))
		{
			if (
				ask("An old version of unihx was detected. Please note that Unihx has changed how it generated projects since version 0.0.1. Would you like to update it? Note that backing up your project before running this is strongly recommended.")
				&& ask("Please close your Unity Editor application and back up your project before continuing. Continue?")
			)
			{
				// go through all folders
				// if hx-compiled folder, save the meta files and delete the rest
				// go through all Standard Assets/Haxe-Std and Editor/Haxe-Std and delete all files there as well
				// build the project again and copy the meta files as needed
				err('Not implemented yet');
			} else {
				err('Cancelled by the user');
			}
		}
	}

	public function runDefault(targetDir=".")
	{
		if (!exists(targetDir))
		{
			err('"$targetDir" does not exist');
		}

		if (targetDir == "")
			targetDir = ".";
		// look for 'Assets' folder
		var assets = getAssets(targetDir);
		if (assets == null)
			err('Cannot find the Assets folder at "$targetDir"');

		if (assets == "")
			assets = ".";

		checkProjectUpdate(assets);

		if (exists(assets + "/classpaths.hxml"))
			if (sys.io.File.getContent(assets + "/classpaths.hxml").split('\n')[0].trim() == '#this file is automatically generated.')
				deleteFile(assets + "/classpaths.hxml");
		if (!exists(assets + "/classpaths.hxml"))
			sys.io.File.saveContent(assets + '/classpaths.hxml', '# Add any paths that may contain .hx files in here\n# This file should be manually maintained\n\n-cp Scripts\n-cp Standard Assets');

		var hxml = new HxmlProps('$assets/build.hxml');
		if (exists('$assets/build.hxml'))
			hxml.reload();
		hxml.save();

		if (exists(assets + '/params.hxml'))
			if (ask('A params.hxml file was found in your Assets folder. Its use is deprecated and `build.hxml` will be used instead. Would you like to remove it?'))
				deleteFile(assets + '/params.hxml');

		if (!exists(assets + '/../Temp/Unihx'))
			createDirectory(assets + '/../Temp/Unihx');

		//TODO: if on release version, do not compile the bootstrap code; instead use the precompiled .dll
		print("Compiling bootstrap code...");

		var args = ['--cwd',assets,'-cs','../Temp/Unihx/unihx-bootstrap','-D','dll','--macro','include("unihx.pvt.editor")','-debug'];
		hxml.getArguments(args);

		callHaxe(args);
		if (!exists('$assets/Plugins/Editor/Unihx'))
			createDirectory('$assets/Plugins/Editor/Unihx');
		sys.io.File.copy('$assets/../Temp/Unihx/unihx-bootstrap/bin/unihx-bootstrap-Debug.dll','$assets/Plugins/Editor/Unihx/unihx-bootstrap.dll');
		sys.io.File.copy('$assets/../Temp/Unihx/unihx-bootstrap/bin/unihx-bootstrap-Debug.dll.mdb','$assets/Plugins/Editor/Unihx/unihx-bootstrap.dll.mdb');

		var proj = assets + "/../" + Path.withoutDirectory( fullPath(assets + "/..") ) + '.hxproj';
		if (!exists(proj))
			sys.io.File.saveContent(proj, Resource.getString("hxproj"));

		for (f in ['smcs','gmcs'])
		{
			if (!exists(assets + '/$f.rsp'))
			{
				sys.io.File.saveContent(assets+'/$f.rsp', "-nowarn:0109,0114,0219,0429,0168,0162");
			}
		}

		// copy assets to Editor Default Resources
		if (exists(assets + '/Editor Default Resources/Unihx'))
			deleteAll(assets + '/Editor Default Resources/Unihx');
		if (exists(assets + '/Editor Default Resources/unihx'))
			deleteAll(assets + '/Editor Default Resources/unihx');

		createDirectory(assets + '/Editor Default Resources/Unihx');
		var unihx = this.getUnihxPath() + "/extra/assets/icons";
		for (file in readDirectory(unihx))
		{
			if (file.endsWith('.png'))
				copy('$unihx/$file', '$assets/Editor Default Resources/Unihx/$file');
		}
	}

	private function getAssets(dir:String):Null<String>
	{
		var full = fullPath(dir).split('\\').join('/').split('/');
		while (full[full.length-1] == "")
			full.pop();

		var buf = new StringBuf();
		buf.add(".");
		while (full.length > 1)
		{
			var dir = full.join('/');
			for (file in readDirectory(dir))
			{
				if (file == "Assets")
					return buf + '/Assets';
			}
			buf.add('/..');
			full.pop();
		}
		return null;
	}

}
