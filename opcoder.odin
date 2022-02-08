package main

import "core:fmt";
import "core:strconv";
import "core:strings";

Addressing_Mode :: enum
{
	Immediate,
	Zeropage,
	Zeropage_X,
	Zeropage_Y,
	Absolute,
	Absolute_X,
	Absolute_Y,
	Indirect_X,
	Indirect_Y,
	Accumulator,
	Relative,
	Implied,
	Indirect,
}

Flag_Usage :: enum
{
	From_Stack,
	Modified,
	Not_Modified,
	Set,
	Cleared,
	Bit_6,
	Bit_7,
}

Cycle_Mod :: enum
{
	None,
	PageCross,
	Branch,
}

Opcode_Variant :: struct
{
	addressing_mode: Addressing_Mode,
	assembler: string,
	opcode: u8,
	bytes: uint,
	cycles: uint,
	cycle_mod: Cycle_Mod,
}

Opcode_Info :: struct
{
	name: string,
	flag_usage: [6]Flag_Usage,
	variants: [dynamic]Opcode_Variant,
}

/*
ADC
    N	Z	C	I	D	V
    +	+	+	-	-	+
    addressing	assembler	opc	bytes	cycles
    immediate	ADC #oper	69	2	2  
    zeropage	ADC oper	65	2	3  
    zeropage,X	ADC oper,X	75	2	4  
    absolute	ADC oper	6D	3	4  
    absolute,X	ADC oper,X	7D	3	4* 
    absolute,Y	ADC oper,Y	79	3	4* 
    (indirect,X)ADC (oper,X)	61	2	6  
    (indirect),YADC (oper),Y	71	2	5* 
*/

/*
Legend to Flags:
+ modified
- not modified
1 set
0 cleared
M6 memory bit 6
M7 memory bit 7 
*/

/*
* add 1 to cycles if page boundary is crossed
** add 1 to cycles if branch occurs on same page, add 2 to cycles if branch occurs to different page 
*/

ParseOpcodeInfos :: proc(text: string) -> ([dynamic]Opcode_Info, map[string]int)
{
	infos    := make([dynamic]Opcode_Info);
	name_map := make(map[string]int);

	lines := strings.split(text, "\r\n");
	lines  = lines[:len(lines)-1];

	cursor := 0;
	for cursor < len(lines)
	{
		name := lines[cursor][:3];

		info := Opcode_Info{ name = name, variants = make([dynamic]Opcode_Variant) };
		cursor += 1;

		for !strings.contains(lines[cursor], "N\tZ\tC\tI\tD\tV") do cursor += 1;

		// Skip labels for flag usage
		cursor += 1;

		if strings.contains(lines[cursor], "from stack") do for flag in &info.flag_usage do flag = .From_Stack;
		else
		{
			flag_usage_string, _ := strings.remove_all(lines[cursor], " ");
			flag_usage_string, _  = strings.remove_all(flag_usage_string, "\t");
			flag_usage_string, _  = strings.remove_all(flag_usage_string, "M");

			for c, i in flag_usage_string
			{
				switch c
				{
					case '+': info.flag_usage[i] = .Modified;     break;
					case '-': info.flag_usage[i] = .Not_Modified; break;
					case '1': info.flag_usage[i] = .Set;          break;
					case '0': info.flag_usage[i] = .Cleared;      break;
					case '6': info.flag_usage[i] = .Bit_6;        break;
					case '7': info.flag_usage[i] = .Bit_7;        break;
				}
			}
		}

		cursor += 1;

		// Skip labels for table
		cursor += 1;

		for cursor < len(lines) && lines[cursor][0] == ' '
		{
			variant: Opcode_Variant;

			row := strings.trim_left_space(lines[cursor]);
			cursor += 1;

			addressing_mode := row[:strings.index(row, "\t")];
			row = strings.trim_left_space(row[len(addressing_mode):]);
		
			if      addressing_mode == "immediate"    do variant.addressing_mode = .Immediate;
			else if addressing_mode == "zeropage"     do variant.addressing_mode = .Zeropage;
			else if addressing_mode == "zeropage,X"   do variant.addressing_mode = .Zeropage_X;
			else if addressing_mode == "zeropage,Y"   do variant.addressing_mode = .Zeropage_Y;
			else if addressing_mode == "absolute"     do variant.addressing_mode = .Absolute;
			else if addressing_mode == "absolute,X"   do variant.addressing_mode = .Absolute_X;
			else if addressing_mode == "absolute,Y"   do variant.addressing_mode = .Absolute_Y;
			else if addressing_mode == "(indirect,X)" do variant.addressing_mode = .Indirect_X;
			else if addressing_mode == "(indirect),Y" do variant.addressing_mode = .Indirect_Y;
			else if addressing_mode == "accumulator"  do variant.addressing_mode = .Accumulator;
			else if addressing_mode == "relative"     do variant.addressing_mode = .Relative;
			else if addressing_mode == "implied"      do variant.addressing_mode = .Implied;
			else if addressing_mode == "indirect"     do variant.addressing_mode = .Indirect;
			else do assert(false);

			variant.assembler = row[:strings.index(row, "\t")];
			row = strings.trim_left_space(row[len(variant.assembler):]);

			opcode, opcode_ok := strconv.parse_int(row[:2], 16);
			assert(opcode_ok);
			row = strings.trim_left_space(row[2:]);

			variant.opcode = u8(opcode);

			bytes, bytes_ok := strconv.parse_int(row[:1], 10);
			assert(bytes_ok);
			row = strings.trim_left_space(row[1:]);

			variant.bytes = uint(bytes);
			
			cycles, cycles_ok := strconv.parse_int(row[:1], 10);
			assert(cycles_ok);
			row = row[1:];

			variant.cycles = uint(cycles);

			row = strings.trim_space(row);
			if      row == ""   do variant.cycle_mod = .None;
			else if row == "*"  do variant.cycle_mod = .PageCross;
			else if row == "**" do variant.cycle_mod = .Branch;
			else do assert(false);

			append(&info.variants, variant);
		}

		name_map[name] = len(infos);
		append(&infos, info);
	}

	return infos, name_map;
}

PrintInfo :: proc(info: Opcode_Info)
{
	fmt.println(info.name);
	fmt.print("\tNZCIDV\n\t");
	for flag in info.flag_usage
	{
		if      flag == .Modified     do fmt.print("+");
		else if flag == .Not_Modified do fmt.print("-");
		else if flag == .Set          do fmt.print("1");
		else if flag == .Cleared      do fmt.print("0");
		else if flag == .Bit_6        do fmt.print("6");
		else                          do fmt.print("7");
	}
	fmt.println();

	for variant in info.variants
	{
		fmt.print("\t");
		
		switch variant.addressing_mode
		{
			case .Immediate:   fmt.print("Immediate"); break;
			case .Zeropage:    fmt.print("Zeropage"); break;
			case .Zeropage_X:  fmt.print("Zeropage_X"); break;
			case .Zeropage_Y:  fmt.print("Zeropage_Y"); break;
			case .Absolute:    fmt.print("Absolute"); break;
			case .Absolute_X:  fmt.print("Absolute_X"); break;
			case .Absolute_Y:  fmt.print("Absolute_Y"); break;
			case .Indirect_X:  fmt.print("Indirect_X"); break;
			case .Indirect_Y:  fmt.print("Indirect_Y"); break;
			case .Accumulator: fmt.print("Accumulator"); break;
			case .Relative:    fmt.print("Relative"); break;
			case .Implied:     fmt.print("Implied"); break;
			case .Indirect:    fmt.print("Indirect"); break;
		}

		fmt.print("\t", variant.assembler);
		fmt.printf("\t%x\t", variant.opcode);
		fmt.print(args = []any{variant.bytes, variant.cycles}, sep = "\t");
		fmt.println("" if variant.cycle_mod == .None else ("*" if variant.cycle_mod == .PageCross else "**"));
	}
}

GroupBySimilarVariants :: proc(infos: []Opcode_Info) -> [dynamic][dynamic]int
{
	ignored_list := make([dynamic]bool);
	for i in 0..len(infos) do append(&ignored_list, false);

	info_groups := make([dynamic][dynamic]int);

	for i in 0..<len(infos)
	{
		if ignored_list[i] do continue;

		info := &infos[i];

		group := make([dynamic]int);
		append(&group, i);
		ignored_list[i] = true;

		j_loop: for j in i+1..<len(infos)
		{
			if ignored_list[j] do continue;

			check_info := &infos[j];

			if len(info.variants) == len(check_info.variants)
			{

				for k in 0..<len(info.variants)
				{
					a := &info.variants[k];
					b := &check_info.variants[k];

					if a.addressing_mode != b.addressing_mode || a.bytes != b.bytes || a.cycles != b.cycles || a.cycle_mod != b.cycle_mod
					{
						continue j_loop;
					}
				}

				append(&group, j);
				ignored_list[j] = true;
			}
		}

		append(&info_groups, group);
	}

	return info_groups;
}

main :: proc()
{
	infos, name_map := ParseOpcodeInfos(string(#load("opcode_list.txt")));

	groups := GroupBySimilarVariants(infos[:]);

	for group in &groups
	{
		for i in group
		{
			fmt.print(infos[i].name, " ");
		}

		fmt.println();
	}
}
