import { useState } from 'react';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { tripApi } from '../api/tripApi';
import type { Trip } from '../api/tripApi';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { getApiError } from '@/lib/utils';

interface ArchiveTripDialogProps {
  trip: Trip | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export function ArchiveTripDialog({ trip, open, onOpenChange }: ArchiveTripDialogProps) {
  const [error, setError] = useState<string | null>(null);
  const queryClient = useQueryClient();

  const archiveMutation = useMutation({
    mutationFn: tripApi.archive,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['trips'] });
      onOpenChange(false);
    },
    onError: (err: any) => {
      setError(getApiError(err, "Erreur lors de l'archivage"));
    }
  });

  const handleArchive = () => {
    if (trip) {
      archiveMutation.mutate(trip.id);
    }
  };

  return (
    <Dialog open={open} onOpenChange={(val) => {
      if (!val) setError(null);
      onOpenChange(val);
    }}>
      <DialogContent className="sm:max-w-[425px]">
        <DialogHeader>
          <DialogTitle>Archiver le voyage</DialogTitle>
          <DialogDescription>
            Êtes-vous sûr de vouloir archiver le voyage pour {trip?.destination} du {trip?.date ? new Date(trip.date).toLocaleDateString() : ''} ? 
            Il n'apparaîtra plus dans la liste principale mais les données seront conservées.
          </DialogDescription>
        </DialogHeader>
        {error && (
          <div className="p-3 bg-red-100 text-red-700 rounded-md text-sm">
            {error}
          </div>
        )}
        <DialogFooter className="mt-4">
          <Button variant="outline" onClick={() => onOpenChange(false)} disabled={archiveMutation.isPending}>
            Annuler
          </Button>
          <Button variant="destructive" onClick={handleArchive} disabled={archiveMutation.isPending}>
            {archiveMutation.isPending ? 'Archivage...' : 'Archiver'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
