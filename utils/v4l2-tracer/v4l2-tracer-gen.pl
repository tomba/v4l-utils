#!/usr/bin/perl
# SPDX-License-Identifier: GPL-2.0-only */
# Copyright 2022 Collabora Ltd.

my $outdir = ".";
my %outtype = ( "common" => 1, "trace" => 1, "retrace" => 1 );

while ($ARGV[0] =~ /^-/) {
	my $arg = shift @ARGV;

	$outdir = shift @ARGV if $arg eq "-o";
	%outtype = (shift @ARGV => 1) if $arg eq '-t';
}

sub convert_type_to_json_type {
	my $type = shift;
	if ($type eq __u8 || $type eq char || $type eq __u16 || $type eq __s8 || $type eq __s16 || $type eq __s32 || $type eq 'int') {
		return "int";
	}
	if ($type eq __u32 || $type eq __le32 || $type eq __s64) {
		return "int64";
	}

	# unsigned appears just twice in videodev2.h and in both cases it is 'unsigned long'
	if ($type eq __u64 || $type eq 'v4l2_std_id' || $type eq 'unsigned') {
		return "uint64";
	}
	if ($type eq struct || $type eq union || $type eq void) {
		return;
	}
	print "v4l2_tracer: error: couldn't convert \'$type\' to json_object type.\n";
	return;
}

sub get_index_letter {
	my $index = shift;
	if ($index eq 0) {return "i";}
	if ($index eq 1) {return "j";}
	if ($index eq 2) {return "k";}
	if ($index eq 3) {return "l";}
	if ($index eq 4) {return "m";}
	if ($index eq 5) {return "n";}
	if ($index eq 6) {return "o";} # "p" is saved for pointer
	if ($index eq 8) {return "q";}
	return "z";
}

$flag_func_name;

sub flag_gen {
	my $flag_type = shift;

	if ($flag_type =~ /fwht/) {
		$flag_func_name = v4l2_ctrl_fwht_params_;
	} elsif ($flag_type =~ /vp8_loop_filter/) {
		$flag_func_name = v4l2_vp8_loop_filter_;
	} else {
		($flag_func_name) = ($_) =~ /#define (\w+_)FL.+/;
		$flag_func_name = lc $flag_func_name;
	}

	printf $fh_common_info_h "constexpr flag_def %sflag_def[] = {\n", $flag_func_name;

	($flag) = ($_) =~ /#define\s+(\w+)\s+.+/;
	printf $fh_common_info_h "\t{ $flag, \"$flag\" },\n"; # get the first flag

	while (<>) {
		next if ($_ =~ /^\/?\s?\*.*/); # skip comments between flags if any
		next if $_ =~ /^\s*$/; # skip blank lines between flags if any
		last if ((grep {!/^#define\s+\w+_FL/} $_) && (grep {!/^#define V4L2_VP8_LF/} $_));
		($flag) = ($_) =~ /#\s*define\s+(\w+)\s+.+/;

		# don't include flags that are masks
		next if ($flag_func_name eq v4l2_buf_) && ($flag =~ /.*TIMESTAMP.*/ || $flag =~ /.*TSTAMP.*/);
		next if ($flag_func_name eq v4l2_ctrl_fwht_params_) && ($flag =~ /.*COMPONENTS.*/ || $flag =~ /.*PIXENC.*/);
		next if ($flag =~ /.*MEDIA_LNK_FL_LINK_TYPE.*/);
		next if ($flag =~ /.*MEDIA_ENT_ID_FLAG_NEXT.*/);

		printf $fh_common_info_h "\t{ $flag, \"$flag\" },\n";
	}
	printf $fh_common_info_h "\t{ 0, \"\" }\n};\n\n";
}

sub enum_gen {
	($enum_name) = ($_) =~ /enum (\w+) {/;
	printf $fh_common_info_h "constexpr val_def %s_val_def[] = {\n", $enum_name;
	while (<>) {
		last if $_ =~ /};/;
		($name) = ($_) =~ /\s+(\w+)\s?.*/;
		next if ($name ne uc $name); # skip comments that don't start with *
		next if ($_ =~ /^\s*\/?\s?\*.*/); # skip comments
		next if $name =~ /^\s*$/;  # skip blank lines
		printf $fh_common_info_h "\t{ %s,\t\"%s\" },\n", $name, $name;
	}
	printf $fh_common_info_h "\t{ -1, \"\" }\n};\n\n";
}

sub clean_up_line {
	my $line = shift;
	chomp($line);
	$line =~ s/^\s+//; # remove leading whitespace
	$line =~ s/.*\# define.*//; # zero out line if it has defines inside a structure (e.g. v4l2_jpegcompression)
	$line =~ s/^\s*\/?\s?\*.*//; # zero out line if it has comments where the line starts with start with /* / * or just *
	$line =~ s/\s*\/\*.*//; # remove comments at the end of a line following a member
	$line =~ s/\*\/$//; # zero out line if it has comments that begin without any slashs or asterisks but end with */
	# zero out lines that don't have a ; or { because they are comments but without any identifying slashes or asteriks
	if ($line !~ /.*[\;|\{].*/) {
		$line =~ s/.*//;
	}
	$line =~ s/.*reserved.*//; # zero out lines with reserved members, they will segfault on retracing
	$line =~ s/.*raw_data.*//;
	# don't remove semi-colon at end because some functions will look for it
	return $line;
}

sub get_val_def_name {
	my @params = @_;
	my $member = @params[0];
	my $struct_name = @params[1];

	$val_def_name = "";
	if ($member =~ /type/) {
		if ($struct_name =~ /.*fmt|format|buf|parm|crop|selection|vbi.*/) {
			$val_def_name = "v4l2_buf_type_val_def";
		} elsif ($struct_name =~ /ctrl$/) {
			$val_def_name = "v4l2_ctrl_type_val_def";
		} else {
			$val_def_name = "nullptr"; # will print as hex string
		}
	}
	if ($member =~ /pixelformat/) {
		$val_def_name = "v4l2_pix_fmt_val_def";
	}
	if ($member =~ /cmd/) {
		if ($struct_name =~ /v4l2_decoder_cmd/) {
			$val_def_name = "decoder_cmd_val_def";
		}
		if ($struct_name =~ /v4l2_encoder_cmd/) {
			$val_def_name = "encoder_cmd_val_def";
		}
	}
	if ($member =~ /memory/) {
		$val_def_name = "v4l2_memory_val_def";
	}
	if ($member =~ /field/) {
		if ($struct_name =~ /.*pix|buffer.*/) {
			$val_def_name = "v4l2_field_val_def";
		} else {
			$val_def_name = "nullptr"; # will print as hex string
		}
	}
	if ($member =~ /^id$/) {
		if ($struct_name =~ /.*control|query.*/) {
			$val_def_name = "control_val_def";
		} else {
			$val_def_name = "nullptr"; # will print as hex string
		}
	}
	if ($member =~ /capability|outputmode|capturemode/) {
		if ($struct_name =~ /.*v4l2_captureparm|v4l2_outputparm.*/) {
		$val_def_name = "streamparm_val_def";
		}
	}
	if ($member =~ /colorspace/) {
		$val_def_name = "v4l2_colorspace_val_def";
	}
	if ($member =~ /ycbcr_enc/) {
		$val_def_name = "v4l2_ycbcr_encoding_val_def";
	}
	if ($member =~ /quantization/) {
		$val_def_name = "v4l2_quantization_val_def";
	}
	if ($member =~ /xfer_func/) {
		$val_def_name = "v4l2_xfer_func_val_def";
	}

	return $val_def_name;
}

sub get_flag_def_name {
	my @params = @_;
	my $member = @params[0];
	my $struct_name = @params[1];

	$flag_def_name = "";
	if ($member =~ /flags/) {
		if ($struct_name =~ /buffers$/) {
			$flag_def_name = "v4l2_memory_flag_def";
		} elsif ($struct_name =~ /.*pix_format.*/) {
			$flag_def_name = "v4l2_pix_fmt_flag_def";
		} elsif ($struct_name =~ /.*ctrl$/) {
			$flag_def_name = "v4l2_ctrl_flag_def";
		} elsif ($struct_name =~ /.*fmtdesc$/) {
			$flag_def_name = "v4l2_fmt_flag_def";
		} elsif ($struct_name =~ /.*selection$/) {
			$flag_def_name = "v4l2_sel_flag_def";
		} else {
			$flag_def_name = "nullptr"
		}
	}

	if ($member =~ /.*cap.*/) {
		# v4l2_requestbuffers, v4l2_create_buffers
		if ($struct_name =~ /buffers$/) {
			$flag_def_name = "v4l2_buf_cap_flag_def";
		}
		# v4l2_capability
		if ($struct_name =~ /capability$/) {
			$flag_def_name = "v4l2_cap_flag_def";
		}
	}

	return $flag_def_name;
}

# trace a struct nested in another struct in videodev2.h
sub handle_struct {
	printf $fh_trace_cpp "\t//$line\n";
	printf $fh_retrace_cpp "\t//$line\n";

	# this is a multi-lined nested struct so iterate through it
	if ($line !~ /.*;$/) {
		$suppress_struct = true;
		return;
	}

	# don't trace struct pointers
	if ($line =~ /\*/) {
		return;
	}
	# don't trace struct arrays
	if ($line =~ /\[/) {
		return;
	}

	my ($struct_tag) = ($line) =~ /\s*struct (\w+)\s+.*/;

	# structs defined outside of videodev2.h
	if ($struct_tag =~ /v4l2_ctrl|timeval|timespec/) {
		return;
	}

	# e.g. $struct_tag_parent = v4l2_captureparm, $struct_tag = v4l2_fract, $struct_var = timeperframe
	my $struct_tag_parent = $struct_name;
	my ($struct_var) = ($line) =~ /(\w+)\;$/;
	printf $fh_trace_cpp "\ttrace_%s_gen(&p->%s, %s_obj, \"%s\");\n", $struct_tag, $struct_var, $struct_tag_parent, $struct_var;

	printf $fh_retrace_cpp "\tvoid *%s_ptr = (void *) retrace_%s_gen(%s_obj, \"%s\");\n", $struct_var, $struct_tag, $struct_tag_parent, $struct_var;
	printf $fh_retrace_cpp "\tp->$struct_var = *static_cast<struct %s*>(%s_ptr);\n", $struct_tag, $struct_var;
	printf $fh_retrace_cpp "\tfree(%s_ptr);\n\n", $struct_var;
}

# trace a union in videodev2.h
sub handle_union {
	my @params = @_;
	my $struct_name = @params[0];

	$in_union = true;
	$suppress_union = true;
	printf $fh_trace_cpp "\t//union\n";
	printf $fh_retrace_cpp "\t//union\n";

	if ($struct_name =~ /^v4l2_pix_format/) {
		$suppress_union = false;
	}

	if ($struct_name =~ /^v4l2_format$/) {
		printf $fh_trace_cpp "\tswitch (p->type) {\n";
		printf $fh_trace_cpp "\tcase V4L2_BUF_TYPE_VIDEO_CAPTURE:\n\tcase V4L2_BUF_TYPE_VIDEO_OUTPUT:\n";
		printf $fh_trace_cpp "\t\ttrace_v4l2_pix_format_gen(&p->fmt.pix, %s_obj);\n\t\tbreak;\n", $struct_name;
		printf $fh_trace_cpp "\tcase V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE:\n\tcase V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE:\n";
		printf $fh_trace_cpp "\t\ttrace_v4l2_pix_format_mplane_gen(&p->fmt.pix, %s_obj);\n\t\tbreak;\n", $struct_name;
		printf $fh_trace_cpp "\tdefault:\n\t\tbreak;\n\t}\n";

		printf $fh_retrace_cpp "\tswitch (p->type) {\n";
		printf $fh_retrace_cpp "\tcase V4L2_BUF_TYPE_VIDEO_CAPTURE:\n\tcase V4L2_BUF_TYPE_VIDEO_OUTPUT: {\n";
		printf $fh_retrace_cpp "\t\tvoid *pix_ptr = (void *) retrace_v4l2_pix_format_gen(v4l2_format_obj);\n";
		printf $fh_retrace_cpp "\t\tp->fmt.pix = *static_cast<struct v4l2_pix_format*>(pix_ptr);\n";
		printf $fh_retrace_cpp "\t\tfree(pix_ptr);\n\t\tbreak;\n\t}\n";

		printf $fh_retrace_cpp "\tcase V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE:\n\tcase V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE: {\n";
		printf $fh_retrace_cpp "\t\tvoid *pix_mp_ptr = (void *) retrace_v4l2_pix_format_mplane_gen(v4l2_format_obj);\n";
		printf $fh_retrace_cpp "\t\tp->fmt.pix_mp = *static_cast<struct v4l2_pix_format_mplane*>(pix_mp_ptr);\n";
		printf $fh_retrace_cpp "\t\tfree(pix_mp_ptr);\n\t\tbreak;\n\t}\n";

		printf $fh_retrace_cpp "\tdefault:\n\t\tbreak;\n\t}\n";
	}

	return $suppress_union;
}

# generate functions for structs in videodev2.h
sub struct_gen {
	($struct_name) = ($_) =~ /struct (\w+) {/;

	# it's not being used and was generating a warning
	if ($struct_name =~ /v4l2_mpeg_vbi_ITV0/) {
		return;
	}
	printf $fh_trace_cpp "void trace_%s_gen(void *arg, json_object *parent_obj, std::string key_name = \"\")\n{\n", $struct_name;
	printf $fh_trace_h "void trace_%s_gen(void *arg, json_object *parent_obj, std::string key_name = \"\");\n", $struct_name;
	printf $fh_trace_cpp "\tjson_object *%s_obj = json_object_new_object();\n", $struct_name;
	printf $fh_trace_cpp "\tstruct %s *p = static_cast<struct %s*>(arg);\n\n", $struct_name, $struct_name;

	printf $fh_retrace_h "struct %s *retrace_%s_gen(json_object *parent_obj, std::string key_name = \"\");\n", $struct_name, $struct_name;
	printf $fh_retrace_cpp "struct %s *retrace_%s_gen(json_object *parent_obj, std::string key_name = \"\")\n{\n", $struct_name, $struct_name;

	printf $fh_retrace_cpp "\tstruct %s *p = (struct %s *) calloc(1, sizeof(%s));\n\n", $struct_name, $struct_name, $struct_name;
	printf $fh_retrace_cpp "\tjson_object *%s_obj;\n", $struct_name;
	printf $fh_retrace_cpp "\tif (key_name.empty())\n";
	printf $fh_retrace_cpp "\t\tjson_object_object_get_ex(parent_obj, \"%s\", &%s_obj);\n", $struct_name, $struct_name;
	printf $fh_retrace_cpp "\telse\n";
	printf $fh_retrace_cpp "\t\tjson_object_object_get_ex(parent_obj, key_name.c_str(), &%s_obj);\n\n", $struct_name;

	$suppress_union = false;
	$suppress_struct = false;
	while ($line = <>) {
		chomp($line);
		$member = "";
		if ($line =~ /}.*;/) {
			if ($suppress_struct eq true) {
				printf $fh_trace_cpp "\t//end of struct $line\n";
				printf $fh_retrace_cpp "\t//end of struct $line\n";
				$suppress_struct = false;
				next;
			} elsif ($in_union eq true) {
				if ($suppress_union eq true) {
					$suppress_union = false; # end of union
				}
				printf $fh_trace_cpp "\t//end of union $line\n";
				printf $fh_retrace_cpp "\t//end of union $line\n";
				$in_union = false;
				next;
			} else {
				last;
			}
		}
		last if $line =~ /^} __attribute__.*/;

		$line = clean_up_line($line);
		next if $line =~ /^\s*$/; # ignore blank lines

		@words = split /[\s\[]/, $line; # split on whitespace and also'[' to get char arrays
		@words = grep  {/^\D/} @words; # remove values that start with digit from inside []
		@words = grep  {!/\]/} @words; # remove values with brackets e.g. V4L2_H264_REF_LIST_LEN]

		($type) = $words[0];

		# unions inside the struct
		if ($type eq 'union') {
			handle_union($struct_name);
			next;
		}
		# suppress anything inside a union including structs nested inside a union
		if ($suppress_union eq true) {
			printf $fh_trace_cpp "\t//$line\n";
			printf $fh_retrace_cpp "\t//$line\n";
			next;
		}

		# struct members inside the struct
		if ($type eq 'struct') {
			handle_struct();
			next;
		}
		if ($suppress_struct eq true) {
			printf $fh_trace_cpp "\t//$line\n";
			printf $fh_retrace_cpp "\t//$line\n";
			next;
		}

		$json_type = convert_type_to_json_type($type);

		($member) = $words[scalar @words - 1];
		$member =~ s/;//; # remove the ;

		if ($member =~ /service_lines/) {
			printf $fh_trace_cpp "\t//$line\n";
			printf $fh_retrace_cpp "\t//$line\n";
			next;
		}

		# Don't trace members that are pointers
		if ($member =~ /\*/) {
			printf $fh_trace_cpp "\t//$line\n";
			printf $fh_retrace_cpp "\t//$line\n";
			next;
		}

		if ($line =~ /dims\[V4L2_CTRL_MAX_DIMS\]/) {
			printf $fh_trace_cpp "\t\/\* $line \*\/\n"; # add comment
			printf $fh_trace_cpp "\tjson_object *dims_obj = json_object_new_array();\n";
			printf $fh_trace_cpp "\tfor (int i = 0; i < (std::min((int) p->nr_of_dims, V4L2_CTRL_MAX_DIMS)); i++) {\n";
			printf $fh_trace_cpp "\t\tjson_object_array_add(dims_obj, json_object_new_int64(p->dims[i]));\n\t}\n";
			printf $fh_trace_cpp "\tjson_object_object_add(%s_obj, \"$member\", dims_obj);\n", $struct_name;

			printf $fh_retrace_cpp "\t\/\* $line \*\/\n"; # add comment
			printf $fh_retrace_cpp "\tjson_object *dims_obj;\n";
			printf $fh_retrace_cpp "\tif (json_object_object_get_ex(%s_obj, \"$member\", &%s_obj)) {\n", $struct_name, $member;
			printf $fh_retrace_cpp "\t\tfor (int i = 0; i < (std::min((int) p->nr_of_dims, V4L2_CTRL_MAX_DIMS)); i++) {\n";
			printf $fh_retrace_cpp "\t\t\tif (json_object_array_get_idx(dims_obj, i))\n";
			printf $fh_retrace_cpp "\t\t\t\tp->dims[i] = (__u32) json_object_get_int64(json_object_array_get_idx(dims_obj, i));\n\t\t}\n\t}\n";
			next;
		}

		printf $fh_retrace_cpp "\tjson_object *%s_obj;\n", $member;

		# struct v4l2_pix_format
		if ($member =~ /priv/) {
			printf $fh_trace_cpp "\tif (p->priv == V4L2_PIX_FMT_PRIV_MAGIC)\n";
			printf $fh_trace_cpp "\t\tjson_object_object_add(%s_obj, \"%s\", json_object_new_string(\"V4L2_PIX_FMT_PRIV_MAGIC\"));\n", $struct_name, $member;
			printf $fh_trace_cpp "\telse\n";
			printf $fh_trace_cpp "\t\tjson_object_object_add(%s_obj, \"%s\", json_object_new_string(\"\"));\n", $struct_name, $member;

			printf $fh_retrace_cpp "\tif (json_object_object_get_ex(%s_obj, \"$member\", &%s_obj)) {\n", $struct_name, $member;
			printf $fh_retrace_cpp "\t\tif (json_object_get_string(priv_obj) == nullptr)\n\t\t\treturn p;\n";
			printf $fh_retrace_cpp "\t\tstd::string priv_str = json_object_get_string(priv_obj);\n";
			printf $fh_retrace_cpp "\t\tif (!priv_str.empty())\n";
			printf $fh_retrace_cpp "\t\t\tp->priv = V4L2_PIX_FMT_PRIV_MAGIC;\n\t}\n";
			next;
		}

		printf $fh_trace_cpp "\tjson_object_object_add(%s_obj, \"%s\", json_object_new_", $struct_name, $member;
		printf $fh_retrace_cpp "\tif (json_object_object_get_ex(%s_obj, \"$member\", &%s_obj))\n", $struct_name, $member;

		# Convert char array members to string
		if ($line =~ /.*\[.*/) {
			if ($member =~ /.*name|driver|card|bus_info|description|model|magic|serial|userbits|APP_data|COM_data|linemask|data|start|count|raw|.*/) {
				printf $fh_trace_cpp "string(reinterpret_cast<const char *>(p->$member)));\n";

				printf $fh_retrace_cpp "\t\tif (json_object_get_string(%s_obj) != nullptr)\n", $member;
				my @char_array_size = ($line) =~ /\[(\w+)\]/g;
				printf $fh_retrace_cpp "\t\t\tmemcpy(p->$member, json_object_get_string(%s_obj), @char_array_size);\n\n", $member;
				next;
			}
		}

		# special strings
		if ($member =~ /version/) {
			printf $fh_trace_cpp "string(ver2s(p->$member).c_str()));\n";
			printf $fh_retrace_cpp "\t\tmemset(&p->$member, 0, sizeof(p->$member));\n\n"; # driver can fill in version
			next;
		}

		printf $fh_retrace_cpp "\t\tp->$member = ";

		if ($struct_name =~ /^v4l2_buffer$/) {
			if ($member =~ /flags/) {
				printf $fh_trace_cpp "string(fl2s_buffer(p->$member).c_str()));\n";
				printf $fh_retrace_cpp "(%s) s2flags_buffer(json_object_get_string(%s_obj));\n\n", $type, $member, $flag_def_name;
				next;
			}
		}

		# strings
		$val_def_name = get_val_def_name($member, $struct_name);
		if ($val_def_name !~ /^\s*$/) {
			printf $fh_trace_cpp "string(val2s(p->$member, %s).c_str()));\n", $val_def_name;
			printf $fh_retrace_cpp "(%s) s2val(json_object_get_string(%s_obj), %s);\n", $type,  $member, $val_def_name;
			next;
		}

		$flag_def_name = get_flag_def_name($member, $struct_name);
		if ($flag_def_name !~ /^\s*$/) {
			printf $fh_trace_cpp "string(fl2s(p->$member, %s).c_str()));\n", $flag_def_name;
			printf $fh_retrace_cpp "(%s) s2flags(json_object_get_string(%s_obj), %s);\n\n", $type, $member, $flag_def_name;
			next;
		}

		# integers
		printf $fh_trace_cpp "$json_type(p->$member));\n";
		printf $fh_retrace_cpp "(%s) json_object_get_%s(%s_obj);\n\n", $type, $json_type, $member;

		# special treatment for v4l2_pix_format_mplane member plane_fmt[VIDEO_MAX_PLANES]
		# it can only be traced after num_planes is known
		if ($member =~ /num_planes/) {
			printf $fh_trace_cpp "\tjson_object *plane_fmt_obj = json_object_new_array();\n";
			printf $fh_trace_cpp "\tfor (int i = 0; i < (std::min((int) p->num_planes, VIDEO_MAX_PLANES)); i++) {\n";
			printf $fh_trace_cpp "\t\tjson_object *element_obj = json_object_new_object();\n";
			printf $fh_trace_cpp "\t\ttrace_v4l2_plane_pix_format_gen(&(p->plane_fmt[i]), element_obj);\n";
			printf $fh_trace_cpp "\t\tjson_object *element_no_key_obj;\n";
			printf $fh_trace_cpp "\t\tjson_object_object_get_ex(element_obj, \"v4l2_plane_pix_format\", &element_no_key_obj);\n";
			printf $fh_trace_cpp "\t\tjson_object_array_add(plane_fmt_obj, element_no_key_obj);\n\t}\n";
			printf $fh_trace_cpp "\tjson_object_object_add(v4l2_pix_format_mplane_obj, \"plane_fmt\", plane_fmt_obj);\n\n";

			printf $fh_retrace_cpp "\tjson_object *plane_fmt_obj;\n";
			printf $fh_retrace_cpp "\tif (json_object_object_get_ex(v4l2_pix_format_mplane_obj, \"plane_fmt\", &plane_fmt_obj)) {\n";
			printf $fh_retrace_cpp "\t\tfor (int i = 0; i < (std::min((int) p->num_planes, VIDEO_MAX_PLANES)); i++) {\n";
			printf $fh_retrace_cpp "\t\t\tif (json_object_array_get_idx(plane_fmt_obj, i)) {\n";
			printf $fh_retrace_cpp "\t\t\t\tjson_object *element_obj = json_object_new_object();\n";
			printf $fh_retrace_cpp "\t\t\t\tjson_object_object_add(element_obj, \"v4l2_plane_pix_format\", json_object_array_get_idx(plane_fmt_obj, i));\n";
			printf $fh_retrace_cpp "\t\t\t\tvoid *ptr = (void *) retrace_v4l2_plane_pix_format_gen(element_obj);\n";
			printf $fh_retrace_cpp "\t\t\t\tp->plane_fmt[i] = *static_cast<struct v4l2_plane_pix_format *>(ptr);\n";
			printf $fh_retrace_cpp "\t\t\t\tfree(ptr);\n";
			printf $fh_retrace_cpp "\t\t\t}\n\t\t}\n\t}\n\n";
		}
	}

	# The key name option allows a struct to be traced when it is nested inside another struct.
	printf $fh_trace_cpp "\n\tif (key_name.empty())\n";
	printf $fh_trace_cpp "\t\tjson_object_object_add(parent_obj, \"%s\", %s_obj);\n", $struct_name, $struct_name;
	printf $fh_trace_cpp "\telse\n";
	printf $fh_trace_cpp "\t\tjson_object_object_add(parent_obj, key_name.c_str(), %s_obj);\n", $struct_name;
	printf $fh_trace_cpp "}\n\n";

	printf $fh_retrace_cpp "\treturn p;\n}\n";
}

# generate functions for structs in v4l2-controls.h
sub struct_gen_ctrl {
	($struct_name) = ($_) =~ /struct (\w+) {/;

	printf $fh_trace_h "void trace_%s_gen(void *ptr, json_object *parent_obj);\n", $struct_name;
	printf $fh_trace_cpp "void trace_%s_gen(void *ptr, json_object *parent_obj)\n{\n", $struct_name;
	printf $fh_trace_cpp "\tjson_object *%s_obj = json_object_new_object();\n", $struct_name;
	printf $fh_trace_cpp "\tstruct %s *p = static_cast<struct %s*>(ptr);\n", $struct_name, $struct_name;

	printf $fh_retrace_h "struct %s *retrace_%s_gen(json_object *ctrl_obj);\n", $struct_name, $struct_name;
	printf $fh_retrace_cpp "struct %s *retrace_%s_gen(json_object *ctrl_obj)\n{\n", $struct_name, $struct_name;
	printf $fh_retrace_cpp "\tstruct %s *p = (struct %s *) calloc(1, sizeof(%s));\n", $struct_name, $struct_name, $struct_name;
	printf $fh_retrace_cpp "\tjson_object *%s_obj;\n", $struct_name;
	# if a key value isn't found, assume it is retracing an element of an array
	# e.g. in struct v4l2_ctrl_h264_pred_weights
	printf $fh_retrace_cpp "\tif (!json_object_object_get_ex(ctrl_obj, \"%s\", &%s_obj))\n", $struct_name, $struct_name;
	printf $fh_retrace_cpp "\t\t%s_obj = ctrl_obj;\n", $struct_name;

	while ($line = <>) {
		chomp($line);
		last if $line =~ /};/;
		$line = clean_up_line($line);
		next if $line =~ /^\s*$/; # ignore blank lines
		$line =~ s/;$//; # remove semi-colon at the end
		@words = split /[\s\[]/, $line; # also split on '[' to avoid arrays
		@words = grep  {/^\D/} @words; # remove values that start with digit from inside []
		@words = grep  {!/\]/} @words; # remove values with brackets e.g. V4L2_H264_REF_LIST_LEN]

		($type) = $words[0];
		$json_type = convert_type_to_json_type($type);

		($member) = $words[scalar @words - 1];

		# generate members that are arrays
		if ($line =~ /.*\[.*/) {
			printf $fh_trace_cpp "\t\/\* %s \*\/\n", $line; # add comment
			printf $fh_trace_cpp "\tjson_object *%s_obj = json_object_new_array();\n", $member;
			printf $fh_retrace_cpp "\n\t\/\* %s \*\/\n", $line; # add comment

			my @dimensions = ($line) =~ /\[(\w+)\]/g;
			$dimensions_count = scalar @dimensions;

			if ($dimensions_count > 1) {
				printf $fh_retrace_cpp "\tint count_%s = 0;\n", $member;
			}
			printf $fh_retrace_cpp "\tjson_object *%s_obj;\n", $member;
			printf $fh_retrace_cpp "\tif (json_object_object_get_ex(%s_obj, \"%s\", &%s_obj)) {\n", $struct_name, $member, $member;

			for (my $idx = 0; $idx < $dimensions_count; $idx = $idx + 1) {
				$size = $dimensions[$idx];
				$index_letter = get_index_letter($idx);
				printf $fh_trace_cpp "\t" x ($idx + 1);
				printf $fh_trace_cpp "for (size_t %s = 0; %s < %s\; %s++) {\n", $index_letter, $index_letter, $size, $index_letter;

				printf $fh_retrace_cpp "\t" x ($idx + 1);
				printf $fh_retrace_cpp "\t";
				printf $fh_retrace_cpp "for (size_t %s = 0; %s < %s\; %s++) {\n", $index_letter, $index_letter, $size, $index_letter;
			}
			printf $fh_trace_cpp "\t" x ($dimensions_count + 1);
			printf $fh_retrace_cpp "\t" x ($dimensions_count + 1);
			printf $fh_retrace_cpp "\t";

			# handle arrays of structs e.g. struct v4l2_ctrl_h264_pred_weights weight_factors
			if ($type =~ /struct/) {
				my $struct_tag = @words[1];
				my $struct_var = $member;
				printf $fh_trace_cpp "json_object *element_obj = json_object_new_object();\n";
				printf $fh_trace_cpp "\t" x ($dimensions_count + 1);
				printf $fh_trace_cpp "trace_%s_gen(&(p->%s", $struct_tag, $struct_var;
				for (my $idx = 0; $idx < $dimensions_count; $idx = $idx + 1) {
					printf $fh_trace_cpp "[%s]", get_index_letter($idx);
				}
				printf $fh_trace_cpp "), element_obj);\n";
				printf $fh_trace_cpp "\t" x ($dimensions_count + 1);
				printf $fh_trace_cpp "json_object *element_no_key_obj;\n";
				printf $fh_trace_cpp "\t" x ($dimensions_count + 1);
				printf $fh_trace_cpp "json_object_object_get_ex(element_obj, \"%s\", &element_no_key_obj);\n", $struct_tag;
				printf $fh_trace_cpp "\t" x ($dimensions_count + 1);
				printf $fh_trace_cpp "json_object_array_add(%s_obj, element_no_key_obj);\n", $struct_var;

				printf $fh_retrace_cpp "void *%s_ptr", $struct_var;
				printf $fh_retrace_cpp " = (void *) retrace_%s_gen(json_object_array_get_idx(%s_obj, ", $struct_tag, $struct_var;
				if ($dimensions_count > 1) {
					printf $fh_retrace_cpp "count_%s++", $struct_var;
				} else {
					printf $fh_retrace_cpp "i";
				}
				printf $fh_retrace_cpp "));\n";

				printf $fh_retrace_cpp "\t" x ($dimensions_count + 1);
				printf $fh_retrace_cpp "\tp->%s", $struct_var;
				for (my $idx = 0; $idx < $dimensions_count; $idx = $idx + 1) {
					printf $fh_retrace_cpp "[%s]", get_index_letter($idx);
				}
				printf $fh_retrace_cpp " = *static_cast<struct %s*>(%s_ptr);\n", $struct_tag, $struct_var;

				printf $fh_retrace_cpp "\t" x ($dimensions_count + 1);
				printf $fh_retrace_cpp "\tfree(%s_ptr);\n", $struct_var;
			} else {
				# handle arrays of ints
				printf $fh_trace_cpp "json_object_array_add(%s_obj, json_object_new_%s(p->%s", $member, $json_type, $member;
				for (my $idx = 0; $idx < $dimensions_count; $idx = $idx + 1) {
					printf $fh_trace_cpp "[%s]", get_index_letter($idx);
				}
				printf $fh_trace_cpp "));\n";

				# add a check to avoid accessing a null array index
				printf $fh_retrace_cpp "if (json_object_array_get_idx(%s_obj, ", $member;
				if ($dimensions_count > 1) {
					printf $fh_retrace_cpp "count_%s", $member;
				} else {
					printf $fh_retrace_cpp "i";
				}
				printf $fh_retrace_cpp "))\n";

				printf $fh_retrace_cpp "\t" x ($dimensions_count + 1);
				printf $fh_retrace_cpp "\t\t";
				printf $fh_retrace_cpp "p->%s", $member;
				for (my $idx = 0; $idx < $dimensions_count; $idx = $idx + 1) {
					printf $fh_retrace_cpp "[%s]", get_index_letter($idx);
				}

				printf $fh_retrace_cpp " = ($type) json_object_get_%s(json_object_array_get_idx(%s_obj, ", $json_type, $member;
				if ($dimensions_count > 1) {
					printf $fh_retrace_cpp "count_%s++", $member;
				} else {
					printf $fh_retrace_cpp "i";
				}
				printf $fh_retrace_cpp "));\n";
			}
			# closing brackets for all array types
			for (my $idx = $dimensions_count - 1; $idx >= 0 ; $idx = $idx - 1) {
				printf $fh_trace_cpp "\t" x ($idx + 1);
				printf $fh_trace_cpp "}\n";

				printf $fh_retrace_cpp "\t" x ($idx + 1);
				printf $fh_retrace_cpp "\t";
				printf $fh_retrace_cpp "}\n";
			}
			printf $fh_retrace_cpp "\t}\n";
			printf $fh_trace_cpp "\tjson_object_object_add(%s_obj, \"%s\", %s_obj);\n\n", $struct_name, $member, $member;
			next;
		}

		# member that is a struct but not an array of structs
		# e.g. $struct_tag_parent = v4l2_ctrl_vp8_frame, $struct_tag = v4l2_vp8_segment, $struct_var = segment
		if ($type =~ /struct/) {
			my $struct_tag_parent = $struct_name;
			my ($struct_tag) = ($line) =~ /\s*struct (\w+)\s+.*/;
			my ($struct_var) = $member;
			printf $fh_trace_cpp "\t\/\* %s \*\/\n", $line;
			printf $fh_trace_cpp "\ttrace_%s_gen(&p->%s, %s_obj);\n", $struct_tag, $struct_var, $struct_tag_parent;

			printf $fh_retrace_cpp "\n\t\/\* %s \*\/\n", $line;
			printf $fh_retrace_cpp "\tjson_object *%s_obj;\n", $struct_var;
			printf $fh_retrace_cpp "\tif (!json_object_object_get_ex(%s_obj, \"%s\", &%s_obj))\n", $struct_tag_parent, $struct_tag, $struct_var;
			printf $fh_retrace_cpp "\t\treturn p;\n", $struct_tag_parent, $struct_tag, $struct_var;

			printf $fh_retrace_cpp "\tvoid *%s_ptr = (void *) retrace_%s_gen(%s_obj);\n", $struct_var, $struct_tag, $struct_var;
			printf $fh_retrace_cpp "\tp->$struct_var = *static_cast<struct %s*>(%s_ptr);\n", $struct_tag, $struct_var;
			printf $fh_retrace_cpp "\tfree(%s_ptr);\n", $struct_var;
			next;
		}

		printf $fh_trace_cpp "\tjson_object_object_add(%s_obj, \"%s\", json_object_new_", $struct_name, $member;
		printf $fh_retrace_cpp "\n\tjson_object *%s_obj;\n", $member;
		printf $fh_retrace_cpp "\tif (json_object_object_get_ex(%s_obj, \"%s\", &%s_obj))\n", $struct_name, $member, $member;

		# strings
		if ($member =~ /flags/) {
			if ($struct_name eq "v4l2_ctrl_fwht_params") {
				printf $fh_trace_cpp "string(fl2s_fwht(p->$member).c_str()));\n";
				printf $fh_retrace_cpp "\t\tp->%s = ($type) s2flags_fwht(json_object_get_string(%s_obj));\n", $member, $member, $flag_func_name;
			} else {
				printf $fh_trace_cpp "string(fl2s(p->$member, %sflag_def).c_str()));\n", $flag_func_name;
				printf $fh_retrace_cpp "\t\tp->%s = ($type) s2flags(json_object_get_string(%s_obj), %sflag_def);\n", $member, $member, $flag_func_name;
			}
			next;
		}

		# Add members with a single string value (e.g. enums, #define)
		$val_def_name = get_val_def_name($member, $struct_name);
		if ($val_def_name !~ /^\s*$/) {
			printf $fh_trace_cpp "string(val2s(p->$member, %s).c_str()));\n", $val_def_name;
			printf $fh_retrace_cpp "\t\tp->%s = ($type) s2val(json_object_get_string(%s_obj), $val_def_name);\n", $member, $member;
			next;
		}

		# integers
		printf $fh_trace_cpp "%s(p->%s));\n", $json_type, $member;
		printf $fh_retrace_cpp "\t\tp->%s = ($type) json_object_get_%s(%s_obj);\n", $member, $json_type, $member;
	}

	printf $fh_trace_cpp "\tjson_object_object_add(parent_obj, \"%s\", %s_obj);\n", $struct_name, $struct_name;
	printf $fh_trace_cpp "}\n\n";

	printf $fh_retrace_cpp "\n\treturn p;\n";
	printf $fh_retrace_cpp "}\n\n";
}

sub do_open($$) {
	my ($type, $fname) = @_;
	my $fh;

	if (defined $outtype{$type}) {
		$fname = "$outdir/$fname";
	} else {
		$fname = "/dev/null";
	}

	open($fh, "> $fname") or die "Could not open $fname for writing";

	return $fh;
}


$fh_trace_cpp = do_open("trace", "trace-gen.cpp");
printf $fh_trace_cpp "/* SPDX-License-Identifier: GPL-2.0-only */\n/*\n * Copyright 2022 Collabora Ltd.\n";
printf $fh_trace_cpp " *\n * AUTOMATICALLY GENERATED BY \'%s\' DO NOT EDIT\n */\n\n", __FILE__;
printf $fh_trace_cpp "#include \"v4l2-tracer-common.h\"\n\n";

$fh_trace_h = do_open("trace", "trace-gen.h");
printf $fh_trace_h "/* SPDX-License-Identifier: GPL-2.0-only */\n/*\n * Copyright 2022 Collabora Ltd.\n";
printf $fh_trace_h " *\n * AUTOMATICALLY GENERATED BY \'%s\' DO NOT EDIT\n */\n\n", __FILE__;
printf $fh_trace_h "\#ifndef TRACE_GEN_H\n";
printf $fh_trace_h "\#define TRACE_GEN_H\n\n";

$fh_retrace_cpp = do_open("retrace", "retrace-gen.cpp");
printf $fh_retrace_cpp "/* SPDX-License-Identifier: GPL-2.0-only */\n/*\n * Copyright 2022 Collabora Ltd.\n";
printf $fh_retrace_cpp " *\n * AUTOMATICALLY GENERATED BY \'%s\' DO NOT EDIT\n */\n\n", __FILE__;
printf $fh_retrace_cpp "#include \"v4l2-tracer-common.h\"\n\n";

$fh_retrace_h = do_open("retrace", "retrace-gen.h");
printf $fh_retrace_h "/* SPDX-License-Identifier: GPL-2.0-only */\n/*\n * Copyright 2022 Collabora Ltd.\n";
printf $fh_retrace_h " *\n * AUTOMATICALLY GENERATED BY \'%s\' DO NOT EDIT\n */\n\n", __FILE__;
printf $fh_retrace_h "\#ifndef RETRACE_GEN_H\n";
printf $fh_retrace_h "\#define RETRACE_GEN_H\n\n";

$fh_common_info_h = do_open("common", "v4l2-tracer-info-gen.h");
printf $fh_common_info_h "/* SPDX-License-Identifier: GPL-2.0-only */\n/*\n * Copyright 2022 Collabora Ltd.\n";
printf $fh_common_info_h " *\n * AUTOMATICALLY GENERATED BY \'%s\' DO NOT EDIT\n */\n\n", __FILE__;
printf $fh_common_info_h "\#ifndef V4L2_TRACER_INFO_GEN_H\n";
printf $fh_common_info_h "\#define V4L2_TRACER_INFO_GEN_H\n\n";
printf $fh_common_info_h "#include \"v4l2-tracer-common.h\"\n\n";

$in_v4l2_controls = true;

while (<>) {
	if (grep {/#define __LINUX_VIDEODEV2_H/} $_) {
		$in_v4l2_controls = false;
	}

	if (grep {/^#define.+FWHT_FL_.+/} $_) {
		flag_gen("fwht");
	} elsif (grep {/^#define V4L2_VP8_LF.*/} $_) {
		flag_gen("vp8_loop_filter");
	} elsif (grep {/^#define.+_FL_.+/} $_) {  #use to get media flags
		flag_gen();
	} elsif (grep {/^#define.+_FLAG_.+/} $_) {
		flag_gen();
	}

	if ($in_v4l2_controls eq true) {
		if (grep {/^struct/} $_) {
			struct_gen_ctrl();
		}
	} else {
		if (grep {/^struct/} $_) {
			struct_gen();
		}
	}

	if (grep {/^enum/} $_) {
		enum_gen();
	}

	if (grep {/^#define\s+(V4L2_CID\w*)\s*.*/} $_) {
		push (@controls, $_);
	}

	if (grep {/^\/\* Control classes \*\//} $_) {
		printf $fh_common_info_h "constexpr val_def ctrlclass_val_def[] = {\n";
		while (<>) {
			last if $_ =~ /^\s*$/; # last if blank line
			($ctrl_class) = ($_) =~ /#define\s*(\w+)\s+.*/;
			printf $fh_common_info_h "\t{ %s,\t\"%s\" },\n", $ctrl_class, $ctrl_class;
		}
		printf $fh_common_info_h "\t{ -1, \"\" }\n};\n\n";
	}

	if (grep {/\/\* Values for 'capabilities' field \*\//} $_) {
		printf $fh_common_info_h "constexpr flag_def v4l2_cap_flag_def[] = {\n";
		while (<>) {
			last if $_ =~ /.*V I D E O   I M A G E   F O R M A T.*/;
			next if ($_ =~ /^\/?\s?\*.*/); # skip comments
			next if $_ =~ /^\s*$/; # skip blank lines
			($cap) = ($_) =~ /#define\s+(\w+)\s+.+/;
			printf $fh_common_info_h "\t{ $cap, \"$cap\" },\n"
		}
		printf $fh_common_info_h "\t{ 0, \"\" }\n};\n\n";
	}

	if (grep {/\*      Pixel format         FOURCC                          depth  Description  \*\//} $_) {
		printf $fh_common_info_h "constexpr val_def v4l2_pix_fmt_val_def[] = {\n";
		while (<>) {
			last if $_ =~ /.*SDR formats - used only for Software Defined Radio devices.*/;
			next if ($_ =~ /^\s*\/\*.*/); # skip comments
			next if $_ =~ /^\s*$/; # skip blank lines
			($pixfmt) = ($_) =~ /#define (\w+)\s+.*/;
			printf $fh_common_info_h "\t{ %s,\t\"%s\" },\n", $pixfmt, $pixfmt;
		}
		printf $fh_common_info_h "\t{ -1, \"\" }\n};\n\n";
	}

	if (grep {/^#define V4L2_BUF_CAP_SUPPORTS_MMAP.*/} $_) {
		printf $fh_common_info_h "constexpr flag_def v4l2_buf_cap_flag_def[] = {\n";
		($buf_cap) = ($_) =~ /#define (\w+)\s+.*/;
		printf $fh_common_info_h "\t{ %s,\t\"%s\" },\n", $buf_cap, $buf_cap;
		while (<>) {
			last if $_ =~ /^\s*$/; # blank line
			($buf_cap) = ($_) =~ /#define (\w+)\s+.*/;
			printf $fh_common_info_h "\t{ %s,\t\"%s\" },\n", $buf_cap, $buf_cap;
		}
		printf $fh_common_info_h "\t{ 0, \"\" }\n};\n\n";
	}

	if (grep {/.*Flags for 'capability' and 'capturemode' fields.*/} $_) {
		printf $fh_common_info_h "constexpr val_def streamparm_val_def[] = {\n";
		while (<>) {
			last if $_ =~ /^\s*$/; # blank line
			($streamparm) = ($_) =~ /^#define\s*(\w+)\s*/;
			printf $fh_common_info_h "\t{ %s,\t\"%s\" },\n", $streamparm, $streamparm;
		}
		printf $fh_common_info_h "\t{ -1, \"\" }\n};\n\n";
	}

	if (grep {/.*V4L2_ENC_CMD_START.*/} $_) {
		printf $fh_common_info_h "constexpr val_def encoder_cmd_val_def[] = {\n";
		($enc_cmd) = ($_) =~ /^#define\s*(\w+)\s*/;
		printf $fh_common_info_h "\t{ %s,\t\"%s\" },\n", $enc_cmd, $enc_cmd;
		while (<>) {
			last if $_ =~ /^\s*$/; # blank line
			($enc_cmd) = ($_) =~ /^#define\s*(\w+)\s*/;
			printf $fh_common_info_h "\t{ %s,\t\"%s\" },\n", $enc_cmd, $enc_cmd;
		}
		printf $fh_common_info_h "\t{ -1, \"\" }\n};\n\n";
	}

	if (grep {/.*Decoder commands.*/} $_) {
		printf $fh_common_info_h "constexpr val_def decoder_cmd_val_def[] = {\n";
		while (<>) {
			last if $_ =~ /^\s*$/; # blank line
			($dec_cmd) = ($_) =~ /^#define\s*(\w+)\s*/;
			printf $fh_common_info_h "\t{ %s,\t\"%s\" },\n", $dec_cmd, $dec_cmd;
		}
		printf $fh_common_info_h "\t{ -1, \"\" }\n};\n\n";
	}

	if (grep {/^#define\s+(VIDIOC_\w*)\s*.*/} $_) {
		push (@ioctls, $_);
	}

	if (grep {/^#define\s+(MEDIA_IOC\w*)\s*.*/} $_) {
		push (@ioctls, $_);
	}

	if (grep {/^#define\s+(MEDIA_REQUEST_IOC\w*)\s*.*/} $_) {
		push (@ioctls, $_);
	}
}

printf $fh_common_info_h "constexpr val_def control_val_def[] = {\n";
foreach (@controls) {
	($control) = ($_) =~ /^#define\s*(\w+)\s*/;
	next if ($control =~ /BASE$/);
	printf $fh_common_info_h "\t{ %s,\t\"%s\" },\n", $control, $control;
}
printf $fh_common_info_h "\t{ -1, \"\" }\n};\n";

printf $fh_common_info_h "constexpr val_def ioctl_val_def[] = {\n";
foreach (@ioctls) {
	($ioctl) = ($_) =~ /^#define\s*(\w+)\s*/;
	printf $fh_common_info_h "\t{ %s,\t\"%s\" },\n", $ioctl, $ioctl;
}
printf $fh_common_info_h "\t{ -1, \"\" }\n};\n";


printf $fh_trace_h "\n#endif\n";
close $fh_trace_h;
close $fh_trace_cpp;

printf $fh_retrace_h "\n#endif\n";
close $fh_retrace_h;
close $fh_retrace_cpp;

printf $fh_common_info_h "\n#endif\n";
close $fh_common_info_h;
