test1:
	cat test1-data.txt | ../gather_jobstats - -M milou -d > test1.out
	@if diff test1.out test1.exp ; then echo "test 1 passed"; rm test1.out; else echo "test 1 FAILED"; fi

.PHONY: test1

