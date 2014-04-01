#!/usr/bin/Rscript

#  !/usr/bin/env Rscript

# see processArgs() for command-line argument structure

.version = "2014-04-01"

# TODO: decide what to do about multiple-node jobs with respect to examineUsage()
# TODO: implement Getopt::Long or some sort of argument processing
# TODO: set limits below using arguments
# TODO: better documentation

options(width=500)

do.plot = TRUE  # produce the plot
col.GB = "black";  lty.GB = 1  # memory lines
col.core = "blue"; lty.core = 2  # core usage lines
col.swap = "red";  pch.swap = 16 # if swap was used

do.flags = TRUE # print list of flags to stdout

.debug = FALSE
sampling.plot.offset = 2.5
sampling.window = 5

# first column in jobstats file for core usage
first.core.column = 6  
# sizes of available nodes for determining misbooking, sorted in increasing mem size
node.types = list(milou= c(mem128GB=128, mem256GB=256, mem512GB=512), milou.default="mem128GB",  
                  kalkyl=c(mem24GB=24, mem48GB=48,  mem72GB=72),      kalkyl.default="mem24GB",
                  tintin=c(mem64GB=64, mem128GB=128),                 tintin.default="mem64GB")

main.line = 5
main.cex = 1.8
main.sep = "  "
flags.line = 2
flags.sep = "   "
flags.line.sep = "\n"
flags.wrap = 3
flags.col = "red3"
flags.cex = 1.2
flag_mem_underused.fraction = 0.25
flag_node_half_underused.fraction = 0.5
flag_node_severely_underused.fraction = 0.25

# process command-line args
processArgs = function(args) {
  job = list()
  if (args[1] == "-n" || args[1] == "--no-plot") {
    do.plot <<- FALSE
    args = args[-1]
  }
  if (args[1] == "-f" || args[1] == "--full") {
    # a full column-wise set of args as produced by the jobstats Perl script
    job$data_type = "full"
    args = args[-1]
    # jobid cluster endtime runtime flags coresbooked core_list node_list jobstats_file_list
    job$jobid = as.integer(args[1])
    job$cluster = as.character(args[2])
    job$endtime = as.character(args[3])
    job$runtime = as.character(args[4])
    job$flag_list = if (args[5] == ".") character(0) else unlist(strsplit(args[5], ",", fixed=TRUE))
    job$booked = if (args[6] == ".") NA else as.integer(args[6])
    job$core_list = as.integer(unlist(strsplit(args[7], ",", fixed=TRUE)))
    job$node_list = unlist(strsplit(args[8], ",", fixed=TRUE))
    job$file_list = unlist(strsplit(args[9], ",", fixed=TRUE))
  } else {
    # arguments are a list of jobstats files
    job$data_type = "file"
    job$cluster = "unknown"
    job$jobid = basename(args[1])
    job$file_list = args
    # dummy up a node list
    job$node_list = job$file_list
  }
  job$data_list = list()
  return(job)
}

# read jobstats file and fill in data.frame attributes
readJobstatsFile = function(file, node="unknown") {
  dat = read.table(file, header=FALSE, skip=1)
  num.cores = ncol(dat) - first.core.column + 1
  names(dat) = c("LOCALTIME", "TIME", "GB_LIMIT", "GB_USED", "GB_SWAP_USED",
                 paste0("core", 1:num.cores))
  attr(dat, "file") = file
  attr(dat, "node") = node
  return(dat)
}

# Look at jobstats data.frame (with attributes) to see if there are
# usage patterns that should be flagged
examineUsage = function(dat) {

  file = attr(dat, "file")
  node = attr(dat, "node")
  cluster = attr(dat, "cluster")

  flag_cores_underused = FALSE  # some cores (apparently) never used
  flag_mem_underused = FALSE   # max mem used < one quarter of mem available
  flag_core_mem_underused = FALSE   # max mem used < one quarter of mem available
  flag_node_half_underused = FALSE   # num cores < max and memory < num cores * core memory fraction
  flag_node_severely_underused = FALSE  # half or less of node used
  flag_node_type_misbooked = FALSE # if on a non-default node, its booking was unnecessary

  num.cores = ncol(dat) - first.core.column + 1
  core.columns = first.core.column:ncol(dat)
  cores.busy = apply(dat[, core.columns, drop=FALSE], 1, function(.x) sum(.x > 0))
  max.cores.busy = max(cores.busy)
  max.GB.avail = max(dat$GB_LIMIT)
  max.GB.used = max(dat$GB_USED)
  core.GB = max.GB.avail / num.cores
  core.mem.used = round(max.cores.busy * core.GB, 1)

  if (! cluster %in% names(node.types)) {
    write(paste0("'", cluster, "' cluster node types not found, cannot check for node_type_misbooked"), 
          stderr())
  } else {
    nt = node.types[[cluster]]
    node.type.booked = names(nt)[which(max.GB.avail <= nt)[1]]
    node.type.needed = names(nt)[which(max.GB.used <= nt)[1]]
    if (! length(node.type.booked) || ! length(node.type.needed)) {
      write(paste0("'", cluster, "' cluster missing a node type, cannot check for node_type_misbooked"), 
            stderr())
    } else {
      if (node.type.booked != node.type.needed) {
        flag_node_type_misbooked = TRUE
      }
    }
  }
  flag_cores_underused = (num.cores > max.cores.busy)
  flag_mem_underused = num.cores > 1 && max.GB.used < (max.GB.avail * flag_mem_underused.fraction)
  flag_core_mem_underused = num.cores > 1 && (flag_cores_underused && (max.GB.used < core.mem.used))
  flag_node_half_underused = (flag_core_mem_underused && 
                              max.cores.busy <= (num.cores * flag_node_half_underused.fraction))
  flag_node_severely_underused = (flag_core_mem_underused && 
                                  max.cores.busy <= (num.cores * flag_node_severely_underused.fraction))

  flag_list = character(0)
  if (flag_cores_underused)
    flag_list = c(flag_list, paste0("cores_underused:", num.cores, ":", max.cores.busy))
  if (flag_mem_underused)
    flag_list = c(flag_list, paste0("mem_underused:", max.GB.avail, ":", max.GB.used))
  if (flag_core_mem_underused)
    flag_list = c(flag_list, paste0("core_mem_underused:", core.mem.used, ":", max.GB.used))
  if (flag_node_half_underused)
    flag_list = c(flag_list, "node_half_underused")
  if (flag_node_severely_underused)
    flag_list = c(flag_list, "node_severely_underused")
  if (flag_node_type_misbooked)
    flag_list = c(flag_list, paste0("node_type_misbooked:", node.type.booked, ":", node.type.needed))
  return(flag_list)
}

# Plot a full set of jobstats panels.  Could be just 1
plotJobstats = function(job, do.png=TRUE) {

  # calculate plot size and layout
  n.panels = length(job$node_list)
  n.jobstats = length(names(job$data_list))
  if (.debug) cat("n.panels =", n.panels, " n.jobstats =", n.jobstats, "\n")

  n.columns = if (n.panels > 1) 2 else 1
  n.rows = if (n.panels > 1) as.integer(n.panels / 2 + 0.5) else 1
  if (.debug) cat("n.columns =", n.columns, " n.rows =", n.rows, "\n")
  width = 800
  top.height = 150
  panel.height = switch (n.panels, "1"=500, "2"=250, n.rows * 250)
  height = top.height + panel.height
  if (.debug) cat("width =", width, " height =", height, "\n")


  if (do.png)
    png(paste0(job$cluster,"-",job$jobid,".png"), width=width, height=height)

  opa = par(no.readonly=TRUE)
  par(mfrow=c(n.rows, n.columns), oma=c(0, 0, 7, 0))
  # plot the individual panels for the nodes for which we have data
  for (n in names(job$data_list)) {
    plotJobstatsPanel( job$data_list[[ n ]], n )
  }
  if (n.panels > n.jobstats) {
    # now plot the individual panels for the unused nodes
    for (n in job$node_list[(n.jobstats+1):n.panels]) {
      plot.new()
      plot.window(xlim=c(0,1), ylim=c(0,1))
      text(0.5, 0.5, paste0("Node ", n, " booked but unused"))
    }
  }

  # Header lines: top line: cluster jobid endtime runtime
  txt = paste(job$jobid, "on", paste0("'", job$cluster, "'"))
  if (! is.null(job$endtime) && job$endtime != ".") 
    txt = paste(sep=main.sep, txt, paste("end:", job$endtime))
  if (! is.null(job$runtime) && job$runtime != ".") 
    txt = paste(sep=main.sep, txt, paste("runtime:", job$runtime))
  mtext(txt, font=2, cex=main.cex, line=main.line, side=3, outer=TRUE)

  # Second line: flags in red
  flags.header = if (n.panels > 1) paste("Flags (based on node", job$node_list[1], "only):") else "Flags:"
  flags.list = character(0)
  if (length(job$flag_list) == 0) {
    flags.list = "none"
  } else if (length(job$flag_list) <= flags.wrap) {
    flags.list = paste(collapse=flags.sep, job$flag_list)
  } else {
    cat
    flags.list = paste(collapse=flags.sep, job$flag_list[1:flags.wrap])
    i = flags.wrap + 1
    while ((i + flags.wrap - 1) <= length(job$flag_list)) {
      j = i + flags.wrap - 1
      flags.list = paste(sep=flags.line.sep, 
                         flags.list, 
                         paste(collapse=flags.sep, job$flag_list[i:j]))
      i = i + flags.wrap
    }
    if (i <= length(job$flag_list)) {
      flags.list = paste(sep=flags.line.sep, 
                        flags.list, 
                        paste(collapse=flags.sep, job$flag_list[i:length(job$flag_list)]))
    }
  }
  txt = paste(flags.header, flags.list)
  mtext(txt, font=1, cex=flags.cex, line=flags.line, side=3, outer=TRUE, col=flags.col)
  par(opa)

  if (do.png)
    graphics.off()
}

plotJobstatsPanel = function(dat, node="unknown") {

  # use job list, already defined in this file

  num.cores = ncol(dat) - first.core.column + 1
  core.columns = first.core.column:ncol(dat)

  # set up plot extents based on resource availability

  range.GB = c(0, dat[1, "GB_LIMIT"])  # GB_LIMIT is fixed for the duration of the job
  range.cores = c(0, num.cores * 100)
  swap.y = range.GB[2]
  # set up traces based on resource usage
  dat$x = ((dat$TIME - dat$TIME[1]) / 60) + sampling.plot.offset  # 5 minute sampling times
  range.x = c(0, max(ceiling(dat$x + sampling.window - sampling.plot.offset)))
  core.at = seq(range.cores[1], range.cores[2], by=100)
  core.labels = paste0(as.character(core.at), "%")
  core.to.GB = function(.x) return((.x / range.cores[2]) * range.GB[2])
  core.at = core.to.GB(core.at)
  dat$core_ = core.to.GB(apply(dat[, core.columns, drop=FALSE], 1, sum))
  dat$swap_ = ifelse(dat$GB_SWAP_USED > 0, swap.y, NA)
  # if just one entry, then max 5 mins, double it to make a line
  if (nrow(dat) == 1) {
    dat = rbind(dat, dat)
    dat$x[1] = 0  # reset left x
    dat$x[2] = sampling.window  # reset right x
  }
  par(mar=c(4,4,2,5.5), las=1, mgp=c(2.0, 0.5, 0), tcl=-0.4)
  #
  with(dat, plot(x, GB_USED, xlim=range.x, ylim=range.GB, 
                 col=col.GB, type="l", lwd=2, lty=lty.GB, 
                 bty="U",
                 main=node, 
                 xlab=paste0("Wall minutes since job start (5 min resolution, max ", 
                             range.x[2], " min)"),
                 ylab=paste0("GB used (max ",range.GB[2]," GB)")))
  with(dat, lines(x, core_, col=col.core, lwd=2, lty=lty.core))
  #
  axis(4, at=core.at, labels=core.labels, col.axis=col.core)
  mtext(paste0("Core busy for ", num.cores, " cores (max ", num.cores * 100,"%)"), 
        side=4, line=3.5, las=0, col=col.core) 
  with(dat, points(x, swap_, pch=16, col="red"))
  if (any(! is.na(dat$swap_)))
    legend("topleft", legend="Swap\nused", bty="n", pch=pch.swap, col=col.swap, 
           text.col=col.swap)

}

gatherAllJobstats = function(job) {
  for (i in 1:length(job$file_list)) {
    node = job$node_list[i]
    job$data_list[[ node ]] = readJobstatsFile(job$file_list[i], node)
    attr(job$data_list[[ node ]], "cluster")  = job$cluster
  }
  job$flag_list = c(job$flag_list, examineUsage(job$data_list[[1]]))
  return(job)
}

args = commandArgs(trailingOnly = TRUE)
if (FALSE && .debug) { cat("after commandArgs()\n"); print(args) }

job = processArgs(args)  # fills job list
if (FALSE && .debug) { cat("after processArgs()\n"); print(job) }

job = gatherAllJobstats(job)
if (.debug) { cat("after gatherAllJobstats()\n"); print(job) }

#  return list of flags 
if (do.flags) {
  write(paste(collapse=",", job$flag_list), stdout())
}

if (do.plot) {
  plotJobstats(job)
}

