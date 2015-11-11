{
open Printf
open Insideout_ast

let pos1 lexbuf = lexbuf.Lexing.lex_start_p
let pos2 lexbuf = lexbuf.Lexing.lex_curr_p
let loc lexbuf = (pos1 lexbuf, pos2 lexbuf)

let string_of_loc (pos1, pos2) =
  let open Lexing in
  let line1 = pos1.pos_lnum
  and start1 = pos1.pos_bol in
  sprintf "File %S, line %i, characters %i-%i"
    pos1.pos_fname line1
    (pos1.pos_cnum - start1)
    (pos2.pos_cnum - start1)

let error lexbuf msg =
  eprintf "%s:\n%s\n%!" (string_of_loc (loc lexbuf)) msg;
  failwith "Aborted"

let read_file lexbuf fname =
  try
    let ic = open_in fname in
    let len = in_channel_length ic in
    let s = Bytes.create len in
    really_input ic s 0 len;
    Bytes.to_string s
  with e ->
    error lexbuf
      (sprintf "Cannot include file %s: %s" fname (Printexc.to_string e))
}

let blank = [' ' '\t']
let space = [' ' '\t' '\r' '\n']
let ident = ['a'-'z']['a'-'z' '_' 'A'-'Z' '0'-'9']*
let graph = ['\033'-'\126']
let format_char = graph # ['\\' ':' '}']
let filename = [^'}']+

rule tokens = parse
  | "${" space* (ident as ident) space*
                                   { let format = opt_format lexbuf in
                                     let default = opt_default lexbuf in
                                     Var { ident; format; default }
                                     :: tokens lexbuf
                                   }
  | "${@" (filename as filename) "}"
                                   (* as-is inclusion, no substitutions,
                                      no escaping *)
                                   { let s = read_file lexbuf filename in
                                     Text s :: tokens lexbuf }
  | "\\$"                          { Text "$" :: tokens lexbuf }
  | "\\\\"                         { Text "\\" :: tokens lexbuf }
  | [^'$''\\']+ as s               { Text s :: tokens lexbuf }
  | _ as c                         { Text (String.make 1 c) :: tokens lexbuf }
  | eof                            { [] }

and opt_format = parse
  | "%" format_char+ as format space*    { Some format }
  | ""                                   { None }

and opt_default = parse
  | ":"    { Some (string [] lexbuf) }
  | "}"    { None }

and string acc = parse
  | "}"                { String.concat "" (List.rev acc) }
  | "\\\\"             { string ("\\" :: acc) lexbuf }
  | "\\}"              { string ("}" :: acc) lexbuf }
  | "\\\n" blank*      { string acc lexbuf }
  | [^'}' '\\']+ as s  { string (s :: acc) lexbuf }
  | _ as c             { string (String.make 1 c :: acc) lexbuf }

{
  open Printf

  let error source msg =
    eprintf "Error in file %s: %s\n%!" source msg;
    exit 1

  let parse_template source ic oc =
    let lexbuf = Lexing.from_channel ic in
    let l = tokens lexbuf in
    let tbl = Hashtbl.create 10 in
    List.iter (
      function
        | Var x ->
            let id = x.ident in
            (try
               let x0 = Hashtbl.find tbl id in
               if x <> x0 then
                 error source (
                   sprintf
                     "Variable %s occurs multiple times with a \n\
                      different %%format or different default value."
                     id
                 )
               else
                 Hashtbl.replace tbl id x
             with Not_found ->
               Hashtbl.add tbl id x
            )
        | Text _ ->
            ()
    ) l;
    tbl, l

}
