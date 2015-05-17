import           Pipe.FileSystem
import           Control.Monad.M
import           Pipe.Conf
import           Options.Applicative
import           Options.Documentation
import qualified Options as O
import qualified Distribution.Package as C
import qualified Data.List as L

import           System.Environment
import           Pipes
import           Options.Cabal
                 
-- | This yields requested packages from command line and cabal file, if any.
-- post-condition: no version overlap in returned 
prod_Dependencies :: O.Options -> ProducerM C.Dependency () 
prod_Dependencies options = do
  cabal_deps <- lift cabalDeps
  each . nub' $ cabal_deps ++ O.packages options
  where
    -- This produces a version disjoint package list from the cabal file.
    cabalDeps :: M [C.Dependency]
    cabalDeps =  
      maybe 
        (return [])
        (`readPackages` O.cabalConstraints options) $ O.cabalFile options

main :: IO ()
main = do 
  -- Check for help mode arg first. There doesn't seem to be a good way to do 
  -- this otherwise with opt-parse applicative.
  args <- getArgs
  case L.partition (== "help") args of 
    ([], args') -> do
      options <- handleParseResult $ execParserPure (prefs idm) parserInfo args'
      -- Run the package processing pipeline. Packages that can't be
      -- completed due to either conversion error or user error, should, if
      -- necessary, leave a safe partially -- completed state on the FS that
      -- can be handled by dependant tools, e.g. Emacs helm-dash.

      runM (newEnv (not . O.quiet $ options)) . runEffect $
        cons_writeFiles (O.outputDir options) -- writes converted html, haddock, and sql db
        <-< pipe_Conf options -- yields vetted package configs
        <-< prod_Dependencies options -- produces dependencies from options 
    (_, rest) -> toHelp docs rest
  
  where 
   parserInfo :: ParserInfo O.Options
   parserInfo = info (helper <*> O.parser)  $
     header "dash-haskell v1.1.0.0, a dash docset construction tool for Haskell packages"
     <> progDesc "additional help is available with \"dash-haskell help <topic|option>\""
     <> footer "http://www.github.com/jfeltz/dash-haskell (C) John P. Feltz 2014, 2015"
