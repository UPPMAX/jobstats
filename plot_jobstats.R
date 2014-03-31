#!/usr/bin/Rscript

#  !/usr/bin/env Rscript


options(width=200)

first.core.column = 6  # first column in jobstats file for core usage


# DONE: handle plot
# DONE: handle plot with just single data point
# DONE: carry through node identity (see jobstats Perl script TODO)
# DONE: wrap flags line
# TODO: add handling of booking too large a node (fat when just 128gb was required)
# TODO: decide what to do about multiple-node jobs with respect to examineUsage()
# TODO: implement Getopt::Long or some sort of argument processing
# TODO: set limits below using arguments
# TODO: make sure general enough to be called directly with jobstats files, if
#       we don't know the node we can always include the filename

flag_mem_underused.fraction = 0.25
flag_node_half_underused.fraction = 0.5
flag_node_severely_underused.fraction = 0.25

# plot_jobstats.R

# arguments are lines produced by 'jobstats' perl script

.version = "2014-03-31"


# process command-line args
processArgs = function(args) {
  job = list()
  if (args[1] == "-f" || args[1] == "--full") {
    # a full column-wise set of args as produced by the jobstats Perl script
    job$data_type = "full"
    args = args[-1]
    # jobid cluster endtime flags coresbooked core_list node_list jobstats_file_list
    job$jobid = as.integer(args[1])
    job$cluster = as.character(args[2])
    job$endtime = as.character(args[3])
    job$flag_list = if (args[4] == ".") character(0) else unlist(strsplit(args[4], ",", fixed=TRUE))
    job$booked = if (args[5] == ".") NA else as.integer(args[5])
    job$core_list = as.integer(unlist(strsplit(args[6], ",", fixed=TRUE)))
    job$node_list = unlist(strsplit(args[7], ",", fixed=TRUE))
    job$file_list = unlist(strsplit(args[8], ",", fixed=TRUE))
  } else {
    # arguments are a list of jobstats files
    job$data_type = "file"
    job$file_list = args
    # dummy up a node list
    job$node_list = paste0("unknown", 1:length(job$file_list))
  }
  job$data_list = list()
  return(job)
}

# read jobstats file and fill in data.frame attributes
readJobstatsFile = function(file, node="unknown") {
  dat = read.table(file, header=FALSE, skip=1)
  num.cores = ncol(dat) - first.core.column + 1
  names(dat) = c("LOCALTIME","TIME","GB_LIMIT","GB_USED","GB_SWAP_USED",paste0("core",1:num.cores))
  attr(dat, "file") = file
  attr(dat, "node") = node
  return(dat)
}

# Look at jobstats data.frame (with attributes) to see if there are
# usage patterns that should be flagged
examineUsage = function(dat) {
  flag_cores_underused = FALSE  # some cores (apparently) never used
  flag_mem_underused = FALSE   # max mem used < one quarter of mem available
  flag_core_mem_underused = FALSE   # max mem used < one quarter of mem available
  flag_node_half_underused = FALSE   # num cores < max and memory < num cores * core memory fraction
  flag_node_severely_underused = FALSE  # half or less of node used

  num.cores = ncol(dat) - first.core.column + 1
  core.columns = first.core.column:ncol(dat)
  cores.busy = apply(dat[, core.columns], 1, function(.x) sum(.x > 0))
  max.cores.busy = max(cores.busy)
  max.GB.avail = max(dat$GB_LIMIT)
  max.GB.used = max(dat$GB_USED)
  core.GB = max.GB.avail / num.cores

  flag_cores_underused = (num.cores > max.cores.busy)
  flag_mem_underused = max.GB.used < (max.GB.avail * flag_mem_underused.fraction)
  flag_core_mem_underused = (flag_cores_underused && (max.GB.used < (max.cores.busy * core.GB)))
  flag_node_half_underused = (flag_core_mem_underused && 
                              max.cores.busy <= (num.cores * flag_node_half_underused.fraction))
  flag_node_severely_underused = (flag_core_mem_underused && 
                                  max.cores.busy <= (num.cores * flag_node_severely_underused.fraction))

  flag_list = character(0)
  if (flag_cores_underused)
    flag_list = c(flag_list, paste0(c("cores_underused:", num.cores, ":", max.cores.busy), collapse=""))
  if (flag_mem_underused)
    flag_list = c(flag_list, paste0(c("mem_underused:", max.GB.avail, ":", max.GB.used), collapse=""))
  if (flag_core_mem_underused)
    flag_list = c(flag_list, paste0(c("core_mem_underused:", (max.cores.busy * core.GB), ":", max.GB.used), collapse=""))
  if (flag_node_half_underused)
    flag_list = c(flag_list, "node_half_underused")
  if (flag_node_severely_underused)
    flag_list = c(flag_list, "node_severely_underused")
  return(flag_list)
}

# Plot a full set of jobstats panels.  Could be just 1
plotJobstats = function(job, do.png=TRUE) {

  # calculate plot size and layout
  n.panels = length(names(job$data_list))
  n.columns = if (n.panels > 1) 2 else 1
  n.rows = if (n.panels > 1) as.integer(n.panels / 2 + 0.5) else 1
  width = 800
  top.height = 150
  panel.height = switch (n.panels, "1"=500, "2"=250, n.rows * 250)
  height = top.height + panel.height
  # cat("width =", width, " height =", height, "\n")


  if (do.png)
    png(paste0(job$cluster,"-",job$jobid,".png"), width=width, height=height)

  opa = par(no.readonly=TRUE)
  par(mfrow=c(n.rows, n.columns), oma=c(0, 0, 7, 0))
  # plot the individual panels
  for (n in job$node_list) {
    plotJobstatsPanel( job$data_list[[ n ]], n )
  }
  # top line: cluster jobid endtime
  txt = paste(job$cluster, "  jobid:", job$jobid)
  if (job$endtime != ".") 
    txt = paste(txt, "  endtime:", job$endtime)
  mtext(txt, font=2, cex=2, line=5, side=3, outer=TRUE)
  # second line: flags in red
  flags.header = if (n.panels > 1) paste("flags (based on node", job$node_list[1], "only):") else "flags:"
  # wrap flags list at 4
  flags.wrap = 4
  flags.list = character(0)
  if (length(job$flag_list) == 0) {
    flags.list = "none"
  } else if (length(job$flag_list) <= flags.wrap) {
    flags.list = paste(collapse=" ", job$flag_list)
  } else {
    flags.list = paste(collapse=" ", job$flag_list[1:flags.wrap])
    i = flags.wrap + 1
    while ((i + flags.wrap - 1) <= length(jobs$flag_list)) {
      j = i + flags.wrap - 1
      flags.list = paste(collapse="\n", flags.list, paste(collapse=" ", job$flag_list[i:j]))
      i = i + flags.wrap
    }
    flags.list = paste(collapse="\n", 
                       flags.list, 
                       paste(collapse=" ", job$flag_list[i:length(jobs$flag_list)]))
  }
  txt = paste(flags.header, flags.list)
  mtext(txt, font=1, cex=1, line=2.5, side=3, outer=TRUE, col="red3")
  par(opa)

  if (do.png)
    graphics.off()
}

plotJobstatsPanel = function(dat, node="unknown") {

  # use job list, already defined in this file

  col.GB = "black";  lty.GB = 1
  col.core = "blue"; lty.core = 2
  col.swap = "red";  pch.swap = 16

  num.cores = ncol(dat) - first.core.column + 1
  core.columns = first.core.column:ncol(dat)

  # set up plot extents based on resource availability

  range.GB = c(0, dat[1, "GB_LIMIT"])  # GB_LIMIT is fixed for the duration of the job
  range.cores = c(0, num.cores * 100)
  swap.y = range.GB[2]
  # set up traces based on resource usage
  dat$x = ((dat$TIME - dat$TIME[1]) / 60) + 5  # 5 minute sampling times
  range.x = c(0, max(dat$x))
  core.at = seq(range.cores[1], range.cores[2], by=100)
  core.labels = paste0(as.character(core.at), "%")
  core.to.GB = function(.x) return((.x / range.cores[2]) * range.GB[2])
  core.at = core.to.GB(core.at)
  dat$core_ = core.to.GB(apply(dat[, core.columns], 1, sum))
  dat$swap_ = ifelse(dat$GB_SWAP_USED > 0, swap.y, NA)
  # if just one entry, then max 5 mins, double it to make a line
  if (nrow(dat) == 1) {
    dat = rbind(dat, dat)
    dat$x[1] = 0  # reset leftmost x
  }
  par(mar=c(4,4,2,5.5), las=1, mgp=c(2.0, 0.5, 0), tcl=-0.4)
  #
  with(dat, plot(x, GB_USED, xlim=range.x, ylim=range.GB, 
                 col=col.GB, type="l", lwd=2, lty=lty.GB, 
                 bty="U",
                 main=paste0("Node ", node), 
                 xlab=paste0("Wall minutes since job start (5 min resolution, max ",range.x[2]," min)"),
                 ylab=paste0("GB used (max ",range.GB[2]," GB)")))
  with(dat, lines(x, core_, col=col.core, lwd=2, lty=lty.core))
  #
  axis(4, at=core.at, labels=core.labels, col.axis=col.core)
  mtext(paste0("Core busy for ", num.cores, " cores (max ", num.cores * 100,"%)"), side=4, line=3.5, las=0, col=col.core) 
  with(dat, points(x, swap_, pch=16, col="red"))
  if (any(! is.na(dat$swap_)))
    legend("topleft", legend="Swap\nused", bty="n", pch=pch.swap, col=col.swap, text.col=col.swap)

}

gatherAllJobstats = function(job) {
  for (i in 1:length(job$file_list)) {
    node = job$node_list[i]
    # cat("reading file for node", node, "...\n")
    job$data_list[[ node ]] = readJobstatsFile(job$file_list[i], node)
    # cat("printing data for node", node, "...\n")
    # print(job$data_list[[ node ]])
    # cat("printing attributes for data for node", node, "...\n")
    # print(attributes(job$data_list[[ node ]]))
  }
  job$flag_list = c(job$flag_list, examineUsage(job$data_list[[1]]))
  return(job)
}

job = processArgs(commandArgs(trailingOnly = TRUE))  # fills job list
# cat("after processArgs()\n")
job = gatherAllJobstats(job)
# cat("after gatherAllJobstats(), before plotJobstats()\n")
# cat("printing job...\n")
# print(job)
# cat("creating plot...\n")
plotJobstats(job)
