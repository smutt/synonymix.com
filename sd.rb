#!/usr/bin/env ruby

############
# Requires #
############
require 'tree'
require 'cgi'

#############
# Constants #
#############
# Number of words to compare against before giving up
MaxCompare = 2000000
# Let's be a little more secure than the default
# This is a builtin for Ruby
$SAFE = 2
# Set to true if running from CLI
CLI = false
# Our previously found distances
FN = "booty.txt"

###########
# Globals #
###########
# Array of words already added to the tree
# Stores string words not actual objects
# Necessary to prevent duplication
$added = Array.new
# Our traversal queue
$q = Array.new

###########
# Classes #
###########
class Word
  attr_reader :word, :syns
  
  def initialize(w)
    @word = clean(w)
    @syns = Array.new
    
    cmdBegin = "wn \'"
    cmdEnd = "\' -synsn|grep \"=>\"|sed s/=\\>//"
    cmd = cmdBegin << @word << cmdEnd
    rv = `#{cmd}`

    # Parse our response
    rv.each{ |x|
      if(! x.include?("INSTANCE OF")) # This indicates a proper noun
        y = x.strip.split(",")
        y.each{ |z|
          if(!z.include?("\'"))
            @syns.push(z.strip)
          end
        }
      end
    }
  end

  def clean(str)
    newStr = str.gsub(/[^a-z\s]/, '')
    newStr.untaint
    return newStr
  end
end

####################
# Lonely Functions #
####################
# Converts results into string for storage and presentation
def resultsToStr(res)
  line = String.new
  res.each{ |r|
    line +=  r + ":"
  }
  line.chop!
  
  return line
end

# Saves results to file
# Takes results already converted to string
def saveResults(str)
  f = File.new(FN, "a+")  
  f.puts(str)
  f.close
end

# Prints results
# Takes results already converted to string
def printResults(str)
  if(CLI)
    print str + "\n"
  else
    puts $cgi.header
    
    htmlStart = "<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Strict//EN\" \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd\">"
    htmlStart << "\n </html>"
    htmlStart << "\n  <head>"
    htmlStart << "\n    <meta http-equiv=\"content-type\" content=\"text/html; charset=utf-8\"/>"
    htmlStart << "\n    <title>Synonymic Distance Finder</title>"
    htmlStart << "\n    <link rel=\"stylesheet\" href=\"http://metafarce.com/textpattern/css.php?s=default\" type=\"text/css\" media=\"screen\" />"
    htmlStart << "\n  </head>"
    htmlStart << "\n  <body>"
    htmlStart << "\n    <center>"
    htmlStart << "\n      Please enter two nouns below to find their Synonymic distance"
    htmlStart << "\n      <form method=\"post\" action=\"sd.rb\">"
    htmlStart << "\n        <input name=\"w1\" type=\"text\"></input>-->"
    htmlStart << "\n        <input name=\"w2\" type=\"text\"></input>"
    htmlStart << "\n        <input type=\"submit\" value=\"Go!\"></input>"
    htmlStart << "\n      </form><br><br>"
    print htmlStart

    print "\n<br>" + str

    htmlEnd = "\n    </center>"
    htmlEnd << "\n  </body>"
    htmlEnd << "\n</html>"
    print htmlEnd
  end
end

###################
# Begin Execution #
###################
# Were we invoked from CLI or CGI
if(CLI)
  $w1 = $*[0]
  $w2 = $*[1]
else
  $cgi = CGI.new
  $w1 = $cgi['w1'].strip
  $w2 = $cgi['w2'].strip
end

if($w1 == $w2)
  res = Array.new
  res.push($w1)
  printResults(resultsToStr(res))
  exit
end

start = Word.new($w1)
if(start.syns.empty?)
  if(CLI)
    puts "No synonyms for " + $w1
    exit
  else
    # TODO: Handle this condition for CGI invocation
    exit
  end
end

if(start.syns.include?($w2))
  res = Array.new
  res.push($w1)
  res.push($w2)
  printResults(resultsToStr(res))
  exit
end

# Check our previous searches before searching again
IO.foreach(FN){ |line|
  r = line.split(":")
  r[r.length - 1].strip! # Each line comes with a trailing CR
  if(r[0] == $w1 && r[r.length - 1] == $w2)
    printResults(resultsToStr(r))
    exit
  end
} 

# Prime the tree for search
$rNode = Tree::TreeNode.new("ROOT", start)
$q.push($rNode)
start.syns.each{ |kid|
  if(! $added.include?(kid))
    $rNode << Tree::TreeNode.new(kid, Word.new(kid))
    $added.push(kid)
  end
}

# Perform a breadth first search using the FIFO queue $q
ii = 0
while ii < MaxCompare do
  # Shift a Node off of our FIFO and examine it for match
  # If no match than create child Nodes for its syns
  parent = $q.shift
  if(parent) # Check if we have reached the end of $q
    parent.children.each{ |kid|
      if(kid.content.syns.include?($w2)) # Have we found our word?
        $found = kid
        break
      else
        kid.content.syns.each{ |grandKid|
          if(! $added.include?(grandKid))
            gKidWord = Word.new(grandKid)
            if(gKidWord.syns.empty?) # Check if grandkid is a leaf-node before adding
              $added.push(grandKid)
            else
              kid << Tree::TreeNode.new(grandKid, gKidWord)
              $added.push(grandKid)
            end
          end
        }
        $q.push(kid)
      end
    }

    if($found)
      res = Array.new
      lineage = $found.parentage.reverse
      lineage.each{ |node|
        res.push(node.content.word)
      }
      res.push($found.content.word)
      res.push($w2)

      str = resultsToStr(res)
      saveResults(str)
      printResults(str)
      exit
    end
    ii += 1

  else # There is no connection to be found
    res = Array.new
    res.push($w1)
    res.push("!")
    res.push($w2)

    str = resultsToStr(res)
    saveResults(str)
    printResults(str)
    exit
  end
end

print $w1 + ":" + $w2 + "You have run out of comparisons.  Please insert another $0.25 to continue\n"
