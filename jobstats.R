# trace.R
#
.version = "2014-03-25"

plot.trace = function(f, sys="milou", cores=16, do.png=TRUE)
{
  col.GB = "black"; lty.GB = 1
  col.core = "blue"; lty.core = 2
  col.swap = "red"; pch.swap = 16
  # LOCALTIME  TIME  GB_LIMIT  GB_USED  GB_SWAP_USED  Individual_core_busy_percentages->->->
  dat = read.table(f, header=FALSE, skip=1, 
                   colClasses=c("Date","numeric","numeric","numeric","numeric",rep("numeric",cores)))
  names(dat) = c("LOCALTIME","TIME","GB_LIMIT","GB_USED","GB_SWAP_USED",paste0("core",1:cores))
  if (do.png)
    png(paste0(sys,"-",f,".png"), width=800, height=600)
  # set up plot extents based on resource availability
  range.GB = c(0, dat[1,"GB_LIMIT"])
  range.cores = c(0, cores*100)
  swap.y = range.GB[2]
  # set up traces based on resource usage
  dat$x = ((dat$TIME - dat$TIME[1]) / 60) + 5
  range.x = c(0, max(dat$x))
  core.at = seq(range.cores[1], range.cores[2], by=100)
  core.labels = paste0(as.character(core.at), "%")
  core.to.GB = function(.x) return((.x / range.cores[2]) * range.GB[2])
  core.at = core.to.GB(core.at)
  dat$core = core.to.GB(apply(dat[,6:(6+cores-1)], 1, sum))
  dat$swap = ifelse(dat$GB_SWAP_USED > 0, swap.y, NA)
  par(mar=c(4,4,2,5), las=1, mgp=c(2.0, 0.5, 0), tcl=-0.4)
  with(dat, plot(x, GB_USED, xlim=range.x, ylim=range.GB, 
                 col=col.GB, type="l", lwd=2, lty=lty.GB, 
                 main=paste0(sys, " job ", f), 
                 xlab=paste0("Job wall minute (max ",range.x[2]," minutes)"),
                 ylab=paste0("GB used (max ",range.GB[2]," GB)")))
  with(dat, lines(x, core, col=col.core, lwd=2, lty=lty.core))
  axis(4, at=core.at, labels=core.labels, col.axis=col.core)
  mtext(paste0("Core busy (max ",cores*100,"%)"), side=4, line=3.5, las=0, col=col.core) 
  with(dat, points(x, swap, pch=16, col="red"))
  if (any(! is.na(dat$swap)))
    legend("topleft", legend="Swap\nused", bty="n", pch=pch.swap, col=col.swap, text.col=col.swap)
  if (do.png)
    dev.off()
}
