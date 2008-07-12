(* $Id$ *)

open Format

type wrap =
    [ `Wrap_atoms
    | `Always_wrap
    | `Never_wrap
    | `Force_breaks
    | `No_breaks ]

type list_param = {
  space_after_opening : bool;
  space_after_separator : bool;
  space_before_separator : bool;
  separators_stick_left : bool;
  space_before_closing : bool;
  stick_to_label : bool;
  align_closing : bool;
  wrap_body : wrap;
  indent_body : int
}

let list = {
  space_after_opening = true;
  space_after_separator = true;
  space_before_separator = false;
  separators_stick_left = true;
  space_before_closing = true;
  stick_to_label = true;
  align_closing = true;
  wrap_body = `Wrap_atoms;
  indent_body = 2
}


type label_param = {
  space_after_label : bool;
  indent_after_label : int
}

let label = {
  space_after_label = true;
  indent_after_label = 2;
}


module Param =
struct
  let list_true = {
    space_after_opening = true;
    space_after_separator = true;
    space_before_separator = true;
    separators_stick_left = true;
    space_before_closing = true;
    stick_to_label = true;
    align_closing = true;
    wrap_body = `Wrap_atoms;
    indent_body = 2
  }

  let list_false = {
    space_after_opening = false;
    space_after_separator = false;
    space_before_separator = false;
    separators_stick_left = false;
    space_before_closing = false;
    stick_to_label = false;
    align_closing = false;
    wrap_body = `Wrap_atoms;
    indent_body = 2
  }
    
  let label_true = {
    space_after_label = true;
    indent_after_label = 2;
  }
    
  let label_false = {
    space_after_label = false;
    indent_after_label = 2;
  }
end


type t =
    Atom of string
  | List of (string * string * string * list_param) * t list
  | Label of (t * label_param) * t



module Pretty =
struct

  (*
    Relies on the fact that makr_open_tag and mark_close_tag
    are called exactly once before calling pp_output_string once.
    It's a reasonable assumption although not guaranteed by the 
    documentation of the Format module.
  *)
  let pp_set_escape fmt escape = 
    let print0, flush0 = pp_get_formatter_output_functions fmt () in
    let tagf0 = pp_get_formatter_tag_functions fmt () in
    
    let is_tag = ref false in
    
    let mot tag =
      is_tag := true;
      tagf0.mark_open_tag tag
    in
    
    let mct tag =
      is_tag := true;
      tagf0.mark_close_tag tag
    in
    
    let print s p n =
      if !is_tag then
	(print0 s p n;
	 is_tag := false)
      else
	escape print0 s p n
    in
    
    let tagf = {
      tagf0 with
	mark_open_tag = mot;
	mark_close_tag = mct
    }
    in
    pp_set_formatter_output_functions fmt print flush0;
    pp_set_formatter_tag_functions fmt tagf
      

  (* More handy, less efficient. *)
  let pp_set_escape_string fmt esc =
    let escape print s p n =
      let s0 = String.sub s p n in
      let s1 = esc s0 in
      print s1 0 (String.length s1)
    in
    pp_set_escape fmt escape


  let pp_open_xbox fmt p indent =
    match p.wrap_body with
	`Always_wrap
      | `Never_wrap
      | `Wrap_atoms -> pp_open_hvbox fmt indent
      | `Force_breaks -> pp_open_vbox fmt indent
      | `No_breaks -> pp_open_hbox fmt ()

  let extra_box p l =
    let wrap =
      match p.wrap_body with
	  `Always_wrap -> true
	| `Never_wrap
	| `Force_breaks
	| `No_breaks -> false
	| `Wrap_atoms ->
	    List.for_all (function Atom _ -> true | _ -> false) l
    in
    if wrap then
      ((fun fmt -> pp_open_hovbox fmt 0),
       (fun fmt -> pp_close_box fmt ()))
    else
      ((fun fmt -> ()),
       (fun fmt -> ()))


  let pp_open_nonaligned_box fmt p indent l =
    match p.wrap_body with
	`Always_wrap -> pp_open_hovbox fmt indent
      | `Never_wrap -> pp_open_hvbox fmt indent
      | `Wrap_atoms -> 
	  if List.for_all (function Atom _ -> true | _ -> false) l then
	    pp_open_hovbox fmt indent
	  else
	    pp_open_hvbox fmt indent
      | `Force_breaks -> pp_open_vbox fmt indent
      | `No_breaks -> pp_open_hbox fmt ()


  let rec fprint_t fmt = function
      Atom s -> fprintf fmt "%s" s
    | List ((_, _, _, p) as param, l) ->
	if p.align_closing then
	  fprint_list fmt None param l
	else
	  fprint_list2 fmt param l

    | Label (label, x) -> fprint_pair fmt label x

  and fprint_list_body_stick_left fmt p sep hd tl =
    fprint_t fmt hd;
    List.iter (
      fun x ->
	if p.space_before_separator then
	  pp_print_string fmt " ";
	pp_print_string fmt sep;
	if p.space_after_separator then
	  pp_print_space fmt ()
	else
	  pp_print_cut fmt ();
	fprint_t fmt x
    ) tl

  and fprint_list_body_stick_right fmt p sep hd tl =
    fprint_t fmt hd;
    List.iter (
      fun x ->
	if p.space_before_separator then
	  pp_print_space fmt ()
	else
	  pp_print_cut fmt ();
	pp_print_string fmt sep;
	if p.space_after_separator then
	  pp_print_string fmt " ";
	fprint_t fmt x
    ) tl

  and fprint_opt_label fmt = function
      None -> ()
    | Some (lab, lp) ->
	fprint_t fmt lab;
	if lp.space_after_label then
	  pp_print_string fmt " "

  (* Either horizontal or vertical list *)
  and fprint_list fmt label ((op, sep, cl, p) as param) = function
      [] -> 
	fprint_opt_label fmt label; 
	if p.space_after_opening || p.space_before_closing then
	  fprintf fmt "%s %s" op cl
	else
	  fprintf fmt "%s%s" op cl

    | hd :: tl as l ->

	if tl = [] || p.separators_stick_left then
	  fprint_list_stick_left fmt label param hd tl l
	else
	  fprint_list_stick_right fmt label param hd tl l


  and fprint_list_stick_left fmt label (op, sep, cl, p) hd tl l =
    let indent = p.indent_body in
    pp_open_xbox fmt p indent;
    fprint_opt_label fmt label; 
    pp_print_string fmt op;
    if p.space_after_opening then 
      pp_print_space fmt ()
    else
      pp_print_cut fmt ();
    
    let open_extra, close_extra = extra_box p l in
    open_extra fmt;
    fprint_list_body_stick_left fmt p sep hd tl;
    close_extra fmt;
    
    if p.space_before_closing then
      pp_print_break fmt 1 (-indent)
    else
      pp_print_break fmt 0 (-indent);
    pp_print_string fmt cl;
    pp_close_box fmt ()

  and fprint_list_stick_right fmt label (op, sep, cl, p) hd tl l =
    let base_indent = p.indent_body in
    let sep_indent = 
      String.length sep + (if p.space_after_separator then 1 else 0)
    in
    let indent = base_indent + sep_indent in
    
    pp_open_xbox fmt p indent;
    fprint_opt_label fmt label; 
    pp_print_string fmt op;

    if p.space_after_opening then 
      pp_print_space fmt ()
    else
      pp_print_cut fmt ();

    let open_extra, close_extra = extra_box p l in
    open_extra fmt;

    fprint_t fmt hd;
    List.iter (
      fun x ->
	if p.space_before_separator then
	  pp_print_break fmt 1 (-sep_indent)
	else
	  pp_print_break fmt 0 (-sep_indent);
	pp_print_string fmt sep;
	if p.space_after_separator then
	  pp_print_string fmt " ";
	fprint_t fmt x
    ) tl;

    close_extra fmt;

    if p.space_before_closing then
      pp_print_break fmt 1 (-indent)
    else
      pp_print_break fmt 0 (-indent);
    pp_print_string fmt cl;
    pp_close_box fmt ()



  (* align_closing = false *)
  and fprint_list2 fmt (op, sep, cl, p) = function
      [] -> 
	if p.space_after_opening || p.space_before_closing then
	  fprintf fmt "%s %s" op cl
	else
	  fprintf fmt "%s%s" op cl
    | hd :: tl as l ->
	pp_print_string fmt op;
	if p.space_after_opening then
	  pp_print_string fmt " ";

	pp_open_nonaligned_box fmt p 0 l ;
	if p.separators_stick_left then
	  fprint_list_body_stick_left fmt p sep hd tl
	else
	  fprint_list_body_stick_right fmt p sep hd tl;
	pp_close_box fmt ();

	if p.space_before_closing then
	  pp_print_string fmt " ";
	pp_print_string fmt cl
	  


  (* Printing a label:value pair.
     
     The opening bracket stays on the same line as the key, no matter what,
     and the closing bracket is either on the same line
     or vertically aligned with the beginning of the key. 
  *)
  and fprint_pair fmt ((lab, lp) as label) x =
    match x with
	List ((op, sep, cl, p), l) when p.stick_to_label && p.align_closing -> 
	  fprint_list fmt (Some label) (op, sep, cl, p) l

      | _ -> 
	  let indent = lp.indent_after_label in
	  pp_open_hvbox fmt 0;
	  fprint_t fmt lab;
	  if lp.space_after_label then
	    pp_print_break fmt 1 indent
	  else
	    pp_print_break fmt 0 indent;
	  fprint_t fmt x;
	  pp_close_box fmt ()

  let to_formatter fmt x =
    fprint_t fmt x;
    pp_print_flush fmt ()
      
  let to_buffer buf x =
    let fmt = Format.formatter_of_buffer buf in
    to_formatter fmt x
      
  let to_string x =
    let buf = Buffer.create 500 in
    to_buffer buf x;
    Buffer.contents buf
      
  let to_channel oc x =
    let fmt = formatter_of_out_channel oc in
    to_formatter fmt x
      
  let to_stdout x = to_channel stdout x
  let to_stderr x = to_channel stderr x

end




module Compact =
struct
  open Printf
  
  let rec fprint_t buf = function
      Atom s -> Buffer.add_string buf s
    | List (param, l) -> fprint_list buf param l
    | Label (label, x) -> fprint_pair buf label x
	

  and fprint_list buf (op, sep, cl, _) = function
      [] -> bprintf buf "%s%s" op cl
    | x :: tl ->
	Buffer.add_string buf op;
	fprint_t buf x;
	List.iter (
	  fun x ->
	    Buffer.add_string buf sep;
	    fprint_t buf x
	) tl;
	Buffer.add_string buf cl

  and fprint_pair buf (label, _) x =
    fprint_t buf label;
    fprint_t buf x


  let to_buffer buf x = fprint_t buf x

  let to_string x =
    let buf = Buffer.create 500 in
    to_buffer buf x;
    Buffer.contents buf

  let to_formatter fmt x =
    let s = to_string x in
    Format.fprintf fmt "%s" s;
    pp_print_flush fmt ()

  let to_channel oc x =
    let buf = Buffer.create 500 in
    to_buffer buf x;
    Buffer.output_buffer oc buf

  let to_stdout x = to_channel stdout x
  let to_stderr x = to_channel stderr x
end
