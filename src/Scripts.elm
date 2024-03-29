module Scripts exposing
    ( ParseState(..)
    , Script
    , ScriptLine
    , ScriptPiece(..)
    , ScriptPieceKind(..)
    , actorGuesses
    , applyGuessedActor
    , cueCannonScript
    , cueCannonUrl
    , extractPlainScript
    , makeScriptPieces
    , parseScript
    , parseScriptHelper
    )

import Base64
import Dict
import Dict.Extra
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
            --"http://localhost:8080/?script="
            "https://goofy-mccarthy-23ec73.netlify.app/?script="
    in
    cueCannonScript script
        -- FIXME process non-ascii characters
        |> String.filter (\c -> Char.toCode c < 128)
        |> Base64.encode
        |> (++) baseUrl


cueCannonScript : Script -> String
cueCannonScript script =
    script
        |> scriptEncoder
        |> Json.Encode.encode 0



-- scriptEncoder : Script -> Json.Encode.Value
-- scriptEncoder { title, lines } =
--     Json.Encode.object
--         [ ( "title", Json.Encode.string title )
--         , ( "lines", Json.Encode.list (lineEncoder title) lines )
--         ]


scriptEncoder : Script -> Json.Encode.Value
scriptEncoder { lines } =
    Json.Encode.list (lineEncoder "") lines


lineEncoder : String -> ScriptLine -> Json.Encode.Value
lineEncoder title { speaker, identifier, line } =
    Json.Encode.object
        [ ( "l", Json.Encode.string line )
        , ( "s", Json.Encode.string speaker )
        , ( "p", Json.Encode.string identifier )
        , ( "t", Json.Encode.string "" )
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


makeScriptPieces : List ScriptPiece -> String -> List ScriptPiece
makeScriptPieces oldPieces plain =
    let
        plainLines =
            plain
                |> String.trim
                |> String.split "\n"

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
    | Parsed ParsedState
    | AddingLine String (List ScriptLine) { characterName : String, lineSoFar : String }
    | FailedParse String


type alias ParsedState =
    { title : String, lines : List ScriptLine }


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
            Parsed { title = piece, lines = [] }

        ( TitlePiece, Parsed oldPiece ) ->
            if oldPiece.title == piece then
                Parsed oldPiece

            else
                FailedParse
                    ("Encountered two titles: "
                        ++ piece
                        ++ " and "
                        ++ oldPiece.title
                    )

        ( TitlePiece, AddingLine _ _ _ ) ->
            FailedParse "Encountered"

        ( CharacterPiece, StartingParse ) ->
            AddingLine startingTitle [] { characterName = piece, lineSoFar = "" }

        ( CharacterPiece, Parsed { title, lines } ) ->
            AddingLine title lines { characterName = piece, lineSoFar = "" }

        ( CharacterPiece, AddingLine title lines { characterName, lineSoFar } ) ->
            if lineSoFar == "" then
                FailedParse
                    ("Encountered two Character Pieces in a row: "
                        ++ piece
                        ++ " and "
                        ++ characterName
                    )

            else
                AddingLine title
                    (lines ++ [ { speaker = characterName, identifier = "", line = lineSoFar } ])
                    { characterName = piece, lineSoFar = "" }

        ( LinePiece, StartingParse ) ->
            FailedParse ("Encountered Line Piece without preceding Character Piece: " ++ piece)

        ( LinePiece, Parsed _ ) ->
            FailedParse ("Encountered Line Piece without preceding Character Piece: " ++ piece)

        ( LinePiece, AddingLine title lines { characterName, lineSoFar } ) ->
            AddingLine title lines { characterName = characterName, lineSoFar = lineSoFar ++ " " ++ piece }


parseScript : Maybe String -> List ScriptPiece -> Result String Script
parseScript t scriptPieces =
    let
        start =
            case t of
                Just title ->
                    Parsed { title = title, lines = [] }

                Nothing ->
                    StartingParse

        trimPieces (ScriptPiece kind piece) =
            ScriptPiece kind (String.trim piece)
    in
    case List.foldl parseScriptHelper start (List.map trimPieces scriptPieces) of
        FailedParse s ->
            Err s

        Parsed { title, lines } ->
            Ok (Script title lines)

        AddingLine title lines { characterName, lineSoFar } ->
            Ok (Script title (lines ++ [ { speaker = characterName, identifier = "", line = lineSoFar } ]))

        StartingParse ->
            Err "Script has no cues"


extractPlainScript : List ScriptPiece -> String
extractPlainScript scriptPieces =
    scriptPieces
        |> extractPlainScriptPieces
        |> String.join "\n"


extractPlainScriptPieces : List ScriptPiece -> List String
extractPlainScriptPieces scriptPieces =
    scriptPieces
        |> List.map (\(ScriptPiece _ s) -> s)


extractUnsurePlainScriptPieces : List ScriptPiece -> List String
extractUnsurePlainScriptPieces scriptPieces =
    let
        filterUnsurePieces piece =
            case piece of
                ScriptPiece UnsurePiece s ->
                    Just s

                _ ->
                    Nothing
    in
    List.filterMap filterUnsurePieces scriptPieces


allPrefixesFromUniquePairs pieces =
    pieces
        |> extractUnsurePlainScriptPieces
        |> List.map String.toList
        |> List.Extra.uniquePairs
        |> List.map (\( pairA, pairB ) -> List.Extra.zip pairA pairB)
        |> List.map (List.Extra.takeWhile (\( a, b ) -> a == b))
        |> List.map (List.map Tuple.first)
        |> List.map String.fromList


actorGuesses pieces =
    allPrefixesFromUniquePairs pieces
        |> Dict.Extra.groupBy (\x -> x)
        |> Dict.toList
        |> List.map (\( name, instances ) -> ( name, -(List.length instances) ))
        |> List.sortBy Tuple.second
        |> List.map Tuple.first
        |> List.filter (\x -> String.length x > 1)
        |> List.take 4


applyGuessedActor name pieces =
    let
        endPunctuationMarks =
            [ ' ', ':' ]

        cleanName =
            name
                |> String.toList
                |> List.Extra.dropWhileRight (\c -> List.member c endPunctuationMarks)
                |> String.fromList

        splitGuessedActor piece =
            case piece of
                ScriptPiece UnsurePiece s ->
                    if String.startsWith name s then
                        [ ScriptPiece CharacterPiece cleanName
                        , ScriptPiece LinePiece (String.dropLeft (String.length name) s)
                        ]

                    else
                        [ piece ]

                _ ->
                    [ piece ]
    in
    pieces
        |> List.concatMap splitGuessedActor
