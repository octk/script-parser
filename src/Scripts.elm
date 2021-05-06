module Scripts exposing
    ( ParseState(..)
    , Script
    , ScriptLine
    , ScriptPiece(..)
    , ScriptPieceKind(..)
    , cueCannonUrl
    , extractPlainScript
    , makeScriptPieces
    , parseScript
    , parseScriptHelper
    )

import Base64
import Json.Encode
import List.Extra



--  ____            _       _     _____                       _
-- / ___|  ___ _ __(_)_ __ | |_  | ____|_  ___ __   ___  _ __| |_
-- \___ \ / __| '__| | '_ \| __| |  _| \ \/ / '_ \ / _ \| '__| __|
--  ___) | (__| |  | | |_) | |_  | |___ >  <| |_) | (_) | |  | |_
-- |____/ \___|_|  |_| .__/ \__| |_____/_/\_\ .__/ \___/|_|   \__|
--                   |_|                    |_|
-- Script Export: Turn a script into a link the user can click on


type alias ScriptLine =
    { speaker : String, identifier : String, line : String }


type alias Script =
    { title : String
    , lines : List ScriptLine
    }


cueCannonUrl : Script -> String
cueCannonUrl script =
    let
        baseUrl =
            --"http://localhost:8080/direct?script="
            "https://goofy-mccarthy-23ec73.netlify.app/direct?script="
    in
    scriptEncoder script
        |> Json.Encode.encode 0
        |> Base64.encode
        |> (++) baseUrl


scriptEncoder : Script -> Json.Encode.Value
scriptEncoder { title, lines } =
    Json.Encode.object
        [ ( "lines", Json.Encode.list (lineEncoder title) lines ) ]


lineEncoder : String -> ScriptLine -> Json.Encode.Value
lineEncoder title { speaker, identifier, line } =
    Json.Encode.object
        [ ( "t", Json.Encode.string line )
        , ( "s", Json.Encode.string speaker )
        , ( "l", Json.Encode.string identifier )
        , ( "p", Json.Encode.string title )
        ]



--  ____            _       _     ____                _
-- / ___|  ___ _ __(_)_ __ | |_  |  _ \ __ _ _ __ ___(_)_ __   __ _
-- \___ \ / __| '__| | '_ \| __| | |_) / _` | '__/ __| | '_ \ / _` |
--  ___) | (__| |  | | |_) | |_  |  __/ (_| | |  \__ \ | | | | (_| |
-- |____/ \___|_|  |_| .__/ \__| |_|   \__,_|_|  |___/_|_| |_|\__, |
--                   |_|                                      |___/
-- Script Parsing: Do we have enough info about this script to export it to the app?


type ScriptPiece
    = ScriptPiece ScriptPieceKind String


type
    ScriptPieceKind
    -- FIXME Add "All" type
    = UnsurePiece
    | IgnorePiece
    | CharacterPiece
    | LinePiece
    | StageDirectionPiece
    | TitlePiece


makeScriptPieces : String -> List ScriptPiece -> List ScriptPiece
makeScriptPieces plain oldPieces =
    let
        plainLines =
            String.split "\n" plain

        pieceFromLine line =
            if line == "" then
                ScriptPiece IgnorePiece line

            else
                ScriptPiece UnsurePiece line

        matchingOldPiece i line =
            -- FIXME Can we manipulate newlines / blank lines to preserve more edits?
            case List.Extra.getAt i oldPieces of
                Just (ScriptPiece kind piece) ->
                    if line == piece then
                        ScriptPiece kind line

                    else
                        pieceFromLine line

                _ ->
                    pieceFromLine line
    in
    List.indexedMap matchingOldPiece plainLines


type ParseState
    = StartingParse
    | Parsed String (List ScriptLine)
    | AddingLine String (List ScriptLine) { characterName : String, lineSoFar : String }
    | FailedParse String


startingTitle : String
startingTitle =
    "Untitled"


parseScriptHelper : ScriptPiece -> ParseState -> ParseState
parseScriptHelper (ScriptPiece kind piece) state =
    case ( kind, state ) of
        ( _, FailedParse f ) ->
            FailedParse f

        ( UnsurePiece, _ ) ->
            FailedParse ("Encountered UnsurePiece: " ++ piece)

        ( IgnorePiece, _ ) ->
            state

        ( StageDirectionPiece, _ ) ->
            -- Ignore stage directions for now
            state

        ( TitlePiece, StartingParse ) ->
            Parsed piece []

        ( TitlePiece, Parsed oldTitle _ ) ->
            FailedParse
                ("Encountered two titles: "
                    ++ piece
                    ++ " and "
                    ++ oldTitle
                )

        ( TitlePiece, AddingLine _ _ _ ) ->
            FailedParse "Encountered"

        ( CharacterPiece, StartingParse ) ->
            AddingLine startingTitle [] { characterName = piece, lineSoFar = "" }

        ( CharacterPiece, Parsed title lines ) ->
            AddingLine title lines { characterName = piece, lineSoFar = "" }

        ( CharacterPiece, AddingLine title lines { characterName, lineSoFar } ) ->
            if lineSoFar == "" then
                FailedParse
                    ("Encountered two Character Pieces in a row: "
                        ++ piece
                        ++ " and "
                        ++ characterName
                    )

            else if characterName == piece then
                Parsed title (lines ++ [ { speaker = characterName, identifier = "", line = lineSoFar } ])

            else
                AddingLine title
                    (lines ++ [ { speaker = characterName, identifier = "", line = lineSoFar } ])
                    { characterName = piece, lineSoFar = "" }

        ( LinePiece, StartingParse ) ->
            FailedParse ("Encountered Line Piece without preceding Character Piece: " ++ piece)

        ( LinePiece, Parsed _ _ ) ->
            FailedParse ("Encountered Line Piece without preceding Character Piece: " ++ piece)

        ( LinePiece, AddingLine title lines { characterName, lineSoFar } ) ->
            AddingLine title lines { characterName = characterName, lineSoFar = lineSoFar ++ piece }


parseScript : List ScriptPiece -> Result String Script
parseScript scriptPieces =
    case List.foldl parseScriptHelper StartingParse scriptPieces of
        FailedParse s ->
            Err s

        Parsed title lines ->
            Ok (Script title lines)

        AddingLine title lines { characterName, lineSoFar } ->
            Ok (Script title (lines ++ [ { speaker = characterName, identifier = "", line = lineSoFar } ]))

        StartingParse ->
            Err "No script"


extractPlainScript : List ScriptPiece -> String
extractPlainScript scriptPieces =
    scriptPieces
        |> List.map (\(ScriptPiece _ s) -> s)
        |> String.join "\n"