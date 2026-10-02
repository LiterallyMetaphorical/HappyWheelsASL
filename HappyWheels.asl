//Get ready dear reader... for a doozy.
state("Happy Wheels") {}

startup
{
	#region setting creation
	dynamic[,] _settings =
	{
	{ "Debug", false, "Debug", null },
		{ "Session", true, "Session", "Debug" },
		{ "Loading", true, "Loading", "Debug" },
	};
	for (int i = 0; i < _settings.GetLength(0); i++)
		settings.Add(_settings[i, 0], _settings[i, 1], _settings[i, 2], _settings[i, 3]);
	#endregion

	if (timer.CurrentTimingMethod == TimingMethod.RealTime)
	{
		var timingMessage = MessageBox.Show (
			"This autosplitter times the time spent in levels (Game Time): it pauses while a level loads,\n"+
			"and from a level's win until the next level is entered, for at most 10 seconds.\n"+
			"LiveSplit is currently set to show Real Time.\n"+
			"Would you like to set the timing method to Game Time?",
			"LiveSplit | Happy Wheels",
			MessageBoxButtons.YesNo,MessageBoxIcon.Question
		);

		if (timingMessage == DialogResult.Yes)
		{
			timer.CurrentTimingMethod = TimingMethod.GameTime;
		}
	}

	#region TextComponent
	vars.lcCache = new Dictionary<string, LiveSplit.UI.Components.ILayoutComponent>();
	vars.SetText = (Action<string, object>)((text1, text2) =>
	{
		const string FileName = "LiveSplit.Text.dll";
		LiveSplit.UI.Components.ILayoutComponent lc;

		if (!vars.lcCache.TryGetValue(text1, out lc))
		{
			lc = timer.Layout.LayoutComponents.Reverse().Cast<dynamic>()
				.FirstOrDefault(llc => llc.Path.EndsWith(FileName) && llc.Component.Settings.Text1 == text1)
				?? LiveSplit.UI.Components.ComponentManager.LoadLayoutComponent(FileName, timer);

			vars.lcCache.Add(text1, lc);
		}

		if (!timer.Layout.LayoutComponents.Contains(lc)) timer.Layout.LayoutComponents.Add(lc);
		dynamic tc = lc.Component;
		tc.Settings.Text1 = text1;
		tc.Settings.Text2 = text2.ToString();
	});
	vars.RemoveText = (Action<string>)(text1 =>
	{
		LiveSplit.UI.Components.ILayoutComponent lc;
		if (vars.lcCache.TryGetValue(text1, out lc))
		{
			timer.Layout.LayoutComponents.Remove(lc);
			vars.lcCache.Remove(text1);
		}
	});
	#endregion

	Process renderer = null;
	long cage = 0;
	var names = new Dictionary<uint, string>();
	var pointers = new Dictionary<string, uint>();

	Func<uint, int, uint[]> words = (tagged, count) =>
	{
		var bytes = renderer.ReadBytes((IntPtr)(cage + tagged - 1), 4 * count);
		if (bytes == null) return null;
		var result = new uint[count];
		Buffer.BlockCopy(bytes, 0, result, 0, 4 * count);
		return result;
	};

	Func<uint, string> name = tagged =>
	{
		string text;
		if (names.TryGetValue(tagged, out text)) return text;
		var header = words(tagged, 3);
		var chars = header != null && header[2] > 0 && header[2] <= 64 ? renderer.ReadBytes((IntPtr)(cage + tagged + 11), (int)header[2]) : null;
		text = chars == null ? "" : Encoding.ASCII.GetString(chars);
		uint moved;
		if (pointers.TryGetValue(text, out moved)) names.Remove(moved);
		pointers[text] = tagged;
		names[tagged] = text;
		return text;
	};

	Func<uint, Dictionary<string, uint>> propertiesOf = obj =>
	{
		var head = words(obj, 2);
		var map = head == null ? null : words(head[0], 4);
		if (map == null || (map[3] >> 21 & 1) == 0) return null;
		var dictionary = words(head[1], 8);
		if (dictionary == null) return null;
		uint capacity = dictionary[4] >> 1;
		if (capacity == 0 || capacity > 4096 || (capacity & (capacity - 1)) != 0 || dictionary[1] != 6 + 3 * capacity) return null;
		var entries = words(head[1] + 32, 3 * (int)capacity);
		if (entries == null) return null;
		var result = new Dictionary<string, uint>();
		for (int i = 0; i < entries.Length; i += 3)
			if ((entries[i] & 1) == 1 && entries[i] != 0x11)
				result[name(entries[i])] = entries[i + 1];
		return result;
	};

	uint settingsClass = 0;
	vars.Find = (Func<bool>)(() =>
	{
		names.Clear();
		pointers.Clear();
		var wmi =System.Reflection.Assembly.Load("System.Management, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a");
		dynamic query = Activator.CreateInstance(wmi.GetType("System.Management.ManagementObjectSearcher"),
			"SELECT ProcessId, CommandLine FROM Win32_Process WHERE Name = 'Happy Wheels.exe'");
		foreach (dynamic process in query.Get())
		{
			if (!((string)process["CommandLine"] ?? "").Contains("--type=renderer")) continue;
			renderer = Process.GetProcessById((int)(uint)process["ProcessId"]);
			foreach (var allocation in renderer.MemoryPages(false).GroupBy(page => (long)page.AllocationBase))
			{
				if (allocation.Key % 0x100000000 != 0) continue;
				cage = allocation.Key;
				var blocks = new List<Tuple<long, byte[]>>();
				foreach (var page in allocation)
				{
					var bytes = renderer.ReadBytes(page.BaseAddress, (int)(ulong)page.RegionSize);
					if (bytes != null) blocks.Add(Tuple.Create((long)page.BaseAddress, bytes));
				}
				Func<long, uint> at = address =>
				{
					foreach (var block in blocks)
						if (address >= block.Item1 && address + 4 <= block.Item1 + block.Item2.Length)
							return BitConverter.ToUInt32(block.Item2, (int)(address - block.Item1));
					return 0;
				};
				Func<uint, List<long>> find = value =>
				{
					var hits = new List<long>();
					foreach (var block in blocks)
						for (int i = 0; i + 4 <= block.Item2.Length; i += 4)
							if (BitConverter.ToUInt32(block.Item2, i) == value) hits.Add(block.Item1 + i);
					return hits;
				};
				var key = Encoding.ASCII.GetBytes("CURRENT_VERSION_STRING");
				var strings = new List<long>();
				foreach (var block in blocks)
					for (int i = 8; i + 4 + key.Length <= block.Item2.Length; i += 4)
						if (BitConverter.ToInt32(block.Item2, i) == key.Length && Enumerable.Range(0, key.Length).All(c => block.Item2[i + 4 + c] == key[c]))
							strings.Add(block.Item1 + i - 8);
				foreach (long text in strings)
				{
					foreach (long entry in find((uint)(text - cage + 1)))
						for (long header = entry - 32; header > entry - 32 - 12 * 4096; header -= 12)
						{
							uint capacity = at(header + 16) >> 1;
							if ((at(header) & 1) == 0 || capacity == 0 || (capacity & (capacity - 1)) != 0 || at(header + 4) != 6 + 3 * capacity) continue;
							if ((entry - header - 32) / 12 < capacity)
								foreach (long reference in find((uint)(header - cage + 1)))
								{
									uint owner = (uint)(reference - 4 - cage + 1);
									var properties = propertiesOf(owner);
									if (properties == null || !properties.ContainsKey("CURRENT_VERSION_STRING")) continue;
									settingsClass = owner;
									print("Settings? renderer " + renderer.Id + ", cage " + cage.ToString("X") + ", class at " + (cage + owner - 1).ToString("X"));
									return true;
								}
							break;
						}
				}
			}
		}
		print("Settings? not found");
		return false;
	});

	vars.Read = (Func<dynamic, bool>)(state =>
	{
		var statics = propertiesOf(settingsClass);
		if (statics == null || !statics.ContainsKey("CURRENT_VERSION_STRING")) return false;
		uint session;
		statics.TryGetValue("session", out session);
		bool none = session == 0 || session == 0x2D;
		var properties = none ? new Dictionary<string, uint>() : propertiesOf(session);
		if (properties == null || !none && !properties.ContainsKey("isMenu"))
		{
			print("Read? skipped, the GC is moving the session");
			return true;
		}
		Func<string, uint> get = key => { uint value; return properties.TryGetValue(key, out value) ? value : 0; };
		string kind = none ? "none" : get("isMenu") == 0x71 ? "menu" : get("isReplay") == 0x71 ? "replay" : get("isEditorTest") == 0x71 ? "editor test" : get("hostWindow") != 0 ? "popup" : "level";
		bool real = kind == "level";
		state.Session = kind;
		state.Playing = real && get("inputAllowed") == 0x71;
		state.Won = real && get("inputAllowed") == 0x55;
		state.Building = real && get("inputAllowed") == 0;
		state.Iteration = (int)(get("_iteration") >> 1);
		return true;
	});
	vars.Waiting = false;
	vars.WinClock = new Stopwatch();
	vars.LoadClock = new Stopwatch();
}

init
{
	vars.Search = new Stopwatch();
	current.Session = "none";
	current.Playing = false;
	current.Won = false;
	current.Building = false;
	current.Entered = false;
	current.Iteration = 0;
	vars.Ready = vars.Find() && vars.Read(current);

	#region Text Component
	vars.SetTextIfEnabled = (Action<string, object>)((text1, text2) =>
	{
		if (settings[text1]) vars.SetText(text1, text2);
		else vars.RemoveText(text1);
	});
	#endregion
	if (settings["Debug"])
	{
		vars.SetTextIfEnabled("Session", current.Session);
		vars.SetTextIfEnabled("Loading", current.Building);
		print("Session? " + current.Session);
	}
}

update
{
	if (!vars.Ready && (!vars.Search.IsRunning || vars.Search.ElapsedMilliseconds >= 1000))
	{
		vars.Search.Restart();
		vars.Ready = vars.Find();
	}
	if (vars.Ready && !vars.Read(current))
	{
		print("Settings? lost");
		vars.Ready = false;
		vars.Search.Reset();
	}
	current.Entered = current.Playing && !old.Playing && current.Iteration < 30;
	if (current.Entered)
	{
		vars.Waiting = false;
		print("Level? entered");
	}
	if (current.Won && !old.Won) print("Level? won, in-game " + current.Iteration + " steps (" + (current.Iteration / 30.0).ToString("0.000") + " s)");

	#region Debug Prints
	if (settings["Debug"])
	{
		if (old.Session != current.Session) { vars.SetTextIfEnabled("Session", current.Session); print("Session? " + current.Session); }
		if (old.Building != current.Building)
		{
			if (current.Building) vars.LoadClock.Restart();
			string loading = current.Building ? "True" : "False, last " + vars.LoadClock.Elapsed.TotalSeconds.ToString("0.000") + " s";
			vars.SetTextIfEnabled("Loading", loading);
			print("Loading? " + loading);
		}
	}
	#endregion
}

onStart
{
	vars.Waiting = false;
}

start
{
	if (current.Entered) print("Start? entered a level");
	return current.Entered;
}

isLoading
{
	return vars.Waiting && vars.WinClock.ElapsedMilliseconds < 10000 || current.Building || current.Won && !old.Won;
}

split
{
	if (!current.Won || old.Won || vars.Waiting) return false;
	vars.Waiting = true;
	vars.WinClock.Restart();
	print("Split? won");
	return true;
}
